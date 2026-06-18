<?php
namespace Pterodactyl\Services\Minecraft\Plugins;
use GuzzleHttp\Client;
use Illuminate\Support\Facades\Cache;
use GuzzleHttp\Exception\TransferException;
use GuzzleHttp\Exception\BadResponseException;
class ModrinthPluginService
{
    protected Client $client;
    protected string $userAgent = 'Pterodactyl Panel/v2 (https://pterodactyl.io)';
    public function __construct()
    {
        $this->client = new Client([
            'headers' => [
                'User-Agent' => $this->userAgent,
            ],
            'base_uri' => 'https://api.modrinth.com/v2/',
        ]);
    }
    /**
     * Search for plugins on the provider.
     */
    public function search(string $searchQuery, int $pageSize, int $page, ?string $minecraftVersion = null, ?string $loader = null): array
    {
        try {
            $facets = [
                ["project_type:plugin"],
                ["server_side!=unsupported"],
            ];
            if (!empty($minecraftVersion)) {
                $facets[] = ["versions:$minecraftVersion"];
            }
            if (!empty($loader)) {
                $facets[] = ["categories:$loader"];
            }
            $response = json_decode($this->client->get('search', [
                'query' => [
                    'query' => $searchQuery,
                    'facets' => json_encode($facets),
                    'index' => 'relevance',
                    'offset' => ($page - 1) * $pageSize,
                    'limit' => $pageSize,
                ],
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
        foreach ($response['hits'] as $modrinthPlugin) {
            $plugins[] = [
                'id' => $modrinthPlugin['project_id'],
                'name' => $modrinthPlugin['title'],
                'description' => $modrinthPlugin['description'],
                'url' => 'https://modrinth.com/plugin/' . $modrinthPlugin['slug'],
                'icon_url' => empty($modrinthPlugin['icon_url']) ? null : $modrinthPlugin['icon_url'],
            ];
        }
        return [
            'data' => $plugins,
            'total' => $response['total_hits'],
        ];
    }
    /**
     * Get the versions of a specific plugin for the provider.
     */
    public function versions(string $pluginId): array
    {
        $loaders = $this->getPluginLoaders();
        try {
            $response = json_decode($this->client->get('project/' . $pluginId . '/version', [
                'query' => [
                    'loaders' => json_encode($loaders),
                ],
            ])->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching plugin versions.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [];
        }
        $versions = [];
        foreach ($response as $modrinthPluginVersion) {
            $versions[] = [
                'id' => $modrinthPluginVersion['id'],
                'name' => $modrinthPluginVersion['name'],
            ];
        }
        return $versions;
    }
    public function getDownloadUrl(string $pluginId, string $versionId): string
    {
        try {
            $response = json_decode($this->client->get('version/' . $versionId)->getBody(), true);
            return $response['files'][0]['url'];
        } catch (TransferException $e) {
            throw new \Exception('Failed to get download URL from Modrinth.');
        }
    }
    /**
     * Get available plugin loaders.
     */
    public function getPluginLoaders(): array
    {
        return Cache::remember('modrinth-plugin-loaders', 3600 * 24, function () {
            try {
                $response = json_decode($this->client->get('tag/loader')->getBody(), true);
                $pluginLoaders = [];
                foreach ($response as $loader) {
                    if (in_array('plugin', $loader['supported_project_types'])) {
                        $pluginLoaders[] = $loader['name'];
                    }
                }
                return $pluginLoaders;
            } catch (TransferException $e) {
                return [];
            }
        });
    }
}
