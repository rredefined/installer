<?php
namespace Pterodactyl\Services\Minecraft\Mods;
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
class CurseForgeModService
{
    public const CURSEFORGE_MINECRAFT_GAME_ID = 432;
    public const CURSEFORGE_MINECRAFT_MODS_CLASS_ID = 6;
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
     * Search for mods on the provider.
     */
    public function search(string $searchQuery, int $pageSize, int $page, ?string $minecraftVersion = null): array
    {
        try {
            $query = [
                'index' => ($page - 1) * $pageSize,
                'pageSize' => $pageSize,
                'gameId' => self::CURSEFORGE_MINECRAFT_GAME_ID,
                'classId' => self::CURSEFORGE_MINECRAFT_MODS_CLASS_ID,
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
                logger()->error('Received bad response when fetching mods.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [
                'data' => [],
                'total' => 0,
            ];
        }
        $mods = [];
        foreach ($response['data'] as $curseforgeMod) {
            $mods[] = [
                'id' => (string) $curseforgeMod['id'],
                'name' => $curseforgeMod['name'],
                'description' => $curseforgeMod['summary'],
                'url' => $curseforgeMod['links']['websiteUrl'],
                'icon_url' => $curseforgeMod['logo']['thumbnailUrl'] ?? null,
            ];
        }
        $maximumPage = (10000 - $pageSize) / $pageSize + 1;
        $totalCount = $response['pagination']['totalCount'] ?? 0;
        return [
            'data' => $mods,
            'total' => min($maximumPage * $pageSize, $totalCount),
        ];
    }
    /**
     * Get the versions of a specific mod for the provider.
     */
    public function versions(string $modId): array
    {
        try {
            $response = json_decode($this->client->get('mods/' . $modId . '/files')->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching mod files.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [];
        }
        $versions = [];
        foreach ($response['data'] as $curseforgeModFile) {
            $versions[] = [
                'id' => (string) $curseforgeModFile['id'],
                'name' => $curseforgeModFile['displayName'],
            ];
        }
        return $versions;
    }
    public function getDownloadUrl(string $modId, string $versionId): string
    {
        try {
            $response = json_decode($this->client->get('mods/' . $modId . '/files/' . $versionId . '/download-url')->getBody(), true);
            return $response['data'];
        } catch (TransferException $e) {
            throw new \Exception('Failed to get download URL from CurseForge.');
        }
    }
}
