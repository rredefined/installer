<?php
namespace Pterodactyl\Services\Minecraft\Plugins;
use GuzzleHttp\Client;
use GuzzleHttp\Exception\TransferException;
use GuzzleHttp\Exception\BadResponseException;
enum CurseForgeSortField: int
{
    case Featured = 1;
    case Popularity = 2;
    case LastUpdated = 3;
    case Name = 4;
    case Author = 5;
    case TotalDownloads = 6;
    case Category = 7;
    case GameVersion = 8;
    case EarlyAccess = 9;
    case FeaturedReleased = 10;
    case ReleasedDate = 11;
    case Rating = 12;
}
class CurseForgePluginService
{
    public const CURSEFORGE_MINECRAFT_GAME_ID = 432;
    public const CURSEFORGE_BUKKIT_PLUGINS_CLASS_ID = 5;
    protected Client $client;
    protected string $userAgent = 'Pterodactyl Panel/v2 (https://pterodactyl.io)';
    public function __construct()
    {
        $apiKey = config('services.curseforge.api_key', '');
        $this->client = new Client([
            'headers' => [
                'User-Agent' => $this->userAgent,
                'x-api-key' => $apiKey,
            ],
            'base_uri' => 'https://api.curseforge.com/v1/',
        ]);
    }
    /**
     * Search for plugins on the provider.
     */
    public function search(string $searchQuery, int $pageSize, int $page, ?string $minecraftVersion = null): array
    {
        try {
            $query = [
                'index' => ($page - 1) * $pageSize,
                'pageSize' => $pageSize,
                'gameId' => self::CURSEFORGE_MINECRAFT_GAME_ID,
                'classId' => self::CURSEFORGE_BUKKIT_PLUGINS_CLASS_ID,
                'searchFilter' => $searchQuery,
                'sortField' => CurseForgeSortField::Popularity->value,
                'sortOrder' => 'desc',
            ];
            if (!empty($minecraftVersion)) {
                $query['gameVersion'] = $minecraftVersion;
            }
            $response = json_decode($this->client->get('mods/search', [
                'query' => $query,
            ])->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching plugins.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [
                'data' => [],
                'total' => 0,
            ];
        }
        $plugins = [];
        foreach ($response['data'] as $curseforgePlugin) {
            $plugins[] = [
                'id' => (string) $curseforgePlugin['id'],
                'name' => $curseforgePlugin['name'],
                'description' => $curseforgePlugin['summary'],
                'url' => $curseforgePlugin['links']['websiteUrl'],
                'icon_url' => $curseforgePlugin['logo']['thumbnailUrl'] ?? null,
            ];
        }
        $maximumPage = (10000 - $pageSize) / $pageSize + 1;
        $totalCount = $response['pagination']['totalCount'] ?? 0;
        return [
            'data' => $plugins,
            'total' => min($maximumPage * $pageSize, $totalCount),
        ];
    }
    /**
     * Get the versions of a specific plugin for the provider.
     */
    public function versions(string $pluginId): array
    {
        try {
            $response = json_decode($this->client->get('mods/' . $pluginId . '/files')->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching plugin files.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [];
        }
        $versions = [];
        foreach ($response['data'] as $curseforgePluginFile) {
            $versions[] = [
                'id' => (string) $curseforgePluginFile['id'],
                'name' => $curseforgePluginFile['displayName'],
            ];
        }
        return $versions;
    }
    public function getDownloadUrl(string $pluginId, string $versionId): string
    {
        try {
            $response = json_decode($this->client->get('mods/' . $pluginId . '/files/' . $versionId . '/download-url')->getBody(), true);
            return $response['data'];
        } catch (TransferException $e) {
            throw new \Exception('Failed to get download URL from CurseForge.');
        }
    }
}
