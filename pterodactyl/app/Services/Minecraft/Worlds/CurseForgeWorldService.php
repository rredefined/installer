<?php
namespace Pterodactyl\Services\Minecraft\Worlds;
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
class CurseForgeWorldService
{
    public const CURSEFORGE_MINECRAFT_GAME_ID = 432;
    public const CURSEFORGE_MINECRAFT_WORLDS_CLASS_ID = 17;
    protected Client $client;
    protected string $apiKey;
    protected string $userAgent = 'Pterodactyl Panel/v2 (https://pterodactyl.io)';
    public function __construct()
    {
        $this->apiKey = config('services.curseforge.api_key', '');
        $this->client = new Client([
            'headers' => [
                'User-Agent' => $this->userAgent,
                'x-api-key' => $this->apiKey,
                'Accept' => 'application/json',
            ],
            'base_uri' => 'https://api.curseforge.com/v1/',
            'timeout' => 30,
            'connect_timeout' => 10,
        ]);
    }
    /**
     * Search for worlds on the provider.
     */
    public function search(string $searchQuery, int $pageSize, int $page): array
    {
        try {
            $response = json_decode($this->client->get('mods/search', [
                'query' => [
                    'index' => ($page - 1) * $pageSize,
                    'pageSize' => $pageSize,
                    'gameId' => self::CURSEFORGE_MINECRAFT_GAME_ID,
                    'classId' => self::CURSEFORGE_MINECRAFT_WORLDS_CLASS_ID,
                    'searchFilter' => $searchQuery,
                    'sortField' => CurseForgeSortField::Popularity->value,
                    'sortOrder' => 'desc',
                ],
            ])->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching worlds.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [
                'data' => [],
                'total' => 0,
            ];
        }
        $worlds = [];
        foreach ($response['data'] as $curseforgeWorld) {
            $worlds[] = [
                'id' => (string) $curseforgeWorld['id'],
                'name' => $curseforgeWorld['name'],
                'description' => $curseforgeWorld['summary'],
                'url' => $curseforgeWorld['links']['websiteUrl'],
                'icon_url' => $curseforgeWorld['logo']['thumbnailUrl'] ?? null,
            ];
        }
        $maximumPage = (10000 - $pageSize) / $pageSize + 1;
        return [
            'data' => $worlds,
            'total' => min($maximumPage * $pageSize, $response['pagination']['totalCount']),
        ];
    }
    /**
     * Get the versions of a specific world for the provider.
     */
    public function versions(string $worldId): array
    {
        try {
            $response = json_decode($this->client->get('mods/' . $worldId . '/files')->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching world files.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [];
        }
        $versions = [];
        foreach ($response['data'] as $curseforgeWorldFile) {
            $versions[] = [
                'id' => (string) $curseforgeWorldFile['id'],
                'name' => $curseforgeWorldFile['displayName'],
            ];
        }
        return $versions;
    }
    /**
     * Get the world slug from CurseForge API.
     */
    protected function getWorldSlug(string $worldId): string
    {
        try {
            $response = $this->client->get('mods/' . $worldId);
            $data = json_decode($response->getBody(), true);
            if (empty($data['data']['slug'])) {
                throw new \Exception('Failed to get world slug from CurseForge.');
            }
            return $data['data']['slug'];
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                $statusCode = $e->getResponse()->getStatusCode();
                $errorBody = $e->getResponse()->getBody()->getContents();
                throw new \Exception('CurseForge API Error (' . $statusCode . '): ' . $errorBody);
            }
            throw new \Exception('Failed to connect to CurseForge: ' . $e->getMessage());
        }
    }
    /**
     * Get the download URL for a specific world version.
     * First tries the API endpoint, falls back to the website URL if needed.
     */
    public function getDownloadUrl(string $worldId, string $versionId): array
    {
        try {
            $worldResponse = $this->client->get('mods/' . $worldId);
            $worldData = json_decode($worldResponse->getBody(), true);
            $slug = $worldData['data']['slug'] ?? '';
            $downloadUrl = "https://www.curseforge.com/api/v1/mods/{$worldId}/files/{$versionId}/download";
            return [
                'url' => $downloadUrl,
                'filename' => 'world_' . $worldId . '_' . $versionId . '.zip',
                'use_header' => true,
                'foreground' => false,
                'headers' => [
                    'User-Agent' => $this->userAgent,
                    'x-api-key' => $this->apiKey,
                    'Accept' => 'application/json',
                ]
            ];
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                throw new \Exception('CurseForge API Error (' . $e->getResponse()->getStatusCode() . '): ' . $e->getResponse()->getBody()->getContents());
            }
            throw new \Exception('Failed to connect to CurseForge: ' . $e->getMessage());
        }
    }
}
