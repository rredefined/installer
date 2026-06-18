<?php
namespace Pterodactyl\Services\Minecraft\Plugins;
use GuzzleHttp\Client;
use GuzzleHttp\Exception\TransferException;
use GuzzleHttp\Exception\BadResponseException;
class HangarPluginService
{
    protected Client $client;
    protected string $userAgent = 'Pterodactyl Panel/v2 (https://pterodactyl.io)';
    public const MAX_PAGE_SIZE = 25;
    public function __construct()
    {
        $this->client = new Client([
            'headers' => [
                'User-Agent' => $this->userAgent,
                'Accept' => 'application/json',
            ],
            'base_uri' => 'https://hangar.papermc.io/api/v1/',
        ]);
    }
    public function search(string $searchQuery, int $pageSize, int $page, ?string $minecraftVersion = null): array
    {
        $pageSize = min($pageSize, self::MAX_PAGE_SIZE);
        try {
            $queryParams = [
                'limit' => $pageSize,
                'offset' => ($page - 1) * $pageSize,
                'query' => empty($searchQuery) ? null : $searchQuery,
                'sort' => '-stars',
            ];
            if (!empty($minecraftVersion)) {
                $queryParams['version'] = $minecraftVersion;
                $queryParams['platform'] = 'PAPER';
            }
            $response = json_decode($this->client->get('projects', [
                'query' => $queryParams,
            ])->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching Hangar plugins.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [
                'data' => [],
                'total' => 0,
            ];
        }
        $plugins = [];
        foreach ($response['result'] as $hangarPlugin) {
            $plugins[] = [
                'id' => $hangarPlugin['name'], 
                'name' => $hangarPlugin['name'],
                'description' => $hangarPlugin['description'],
                'url' => 'https://hangar.papermc.io/projects/' . $hangarPlugin['name'],
                'icon_url' => $hangarPlugin['avatarUrl'],
            ];
        }
        return [
            'data' => $plugins,
            'total' => $response['pagination']['count'],
        ];
    }
    public function versions(string $pluginId): array
    {
        try {
            $response = json_decode($this->client->get('projects/' . $pluginId . '/versions', [
                'query' => [
                    'limit' => 100,
                ],
            ])->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching Hangar plugin versions.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [];
        }
        $versions = [];
        foreach ($response['result'] as $version) {
            $versions[] = [
                'id' => $version['name'],
                'name' => $version['name'],
            ];
        }
        return $versions;
    }
    public function getDownloadUrl(string $pluginId, string $versionId): string
    {
        try {
            $response = json_decode($this->client->get('projects/' . $pluginId . '/versions/' . $versionId)->getBody(), true);
            $downloads = $response['downloads'];
            $platform = 'PAPER';
            if (!isset($downloads[$platform])) {
                $platform = array_key_first($downloads);
            }
            if ($platform && isset($downloads[$platform])) {
                return $downloads[$platform]['downloadUrl'] ?? $downloads[$platform]['externalUrl'];
            }
            return 'https://hangar.papermc.io/api/v1/projects/' . $pluginId . '/versions/' . $versionId . '/download';
        } catch (TransferException $e) {
            throw new \Exception('Failed to get download URL from Hangar.');
        }
    }
}
