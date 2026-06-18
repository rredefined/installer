<?php
namespace Pterodactyl\Services\Minecraft\Plugins;
use GuzzleHttp\Client;
use GuzzleHttp\Exception\TransferException;
use GuzzleHttp\Exception\BadResponseException;
class SpigotMCPluginService
{
    protected Client $client;
    protected string $userAgent = 'Pterodactyl Panel/v2 (https://pterodactyl.io)';
    public function __construct()
    {
        $this->client = new Client([
            'headers' => [
                'User-Agent' => $this->userAgent,
            ],
            'base_uri' => 'https://api.spiget.org/v2/',
        ]);
    }
    /**
     * Search for plugins on the provider.
     */
    public function search(string $searchQuery, int $pageSize, int $page, ?string $minecraftVersion = null): array
    {
        $uri = empty($searchQuery) ? 'resources/free' : ('search/resources/' . rawurlencode($searchQuery));
        try {
            $response = $this->client->get($uri, [
                'query' => [
                    'size' => $pageSize,
                    'page' => $page,
                    'sort' => '-likes',
                ],
            ]);
            $total = (int) ($response->getHeader('X-Total-Count')[0] ?? 0);
            $data = json_decode($response->getBody(), true);
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
        foreach ($data as $spigotPlugin) {
            $iconUrl = 'https://www.spigotmc.org/' . ($spigotPlugin['icon']['url'] ?? 'styles/spigot/xenresource/resource_icon.png');
            if (empty($spigotPlugin['icon']['url'])) {
                $iconUrl = null;
            } else {
                 $iconUrl = 'https://www.spigotmc.org/' . $spigotPlugin['icon']['url'];
            }
            $plugins[] = [
                'id' => (string) $spigotPlugin['id'],
                'name' => $spigotPlugin['name'],
                'description' => $spigotPlugin['tag'],
                'url' => 'https://www.spigotmc.org/resources/' . $spigotPlugin['id'],
                'icon_url' => $iconUrl,
            ];
        }
        return [
            'data' => $plugins,
            'total' => $total,
        ];
    }
    /**
     * Get the versions of a specific plugin for the provider.
     */
    public function versions(string $pluginId): array
    {
        try {
            $response = json_decode($this->client->get('resources/' . $pluginId . '/versions', [
                'query' => [
                    'size' => 100, 
                    'sort' => '-releaseDate',
                ]
            ])->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching plugin versions.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [];
        }
        $versions = [];
        foreach ($response as $spigotPluginVersion) {
            $versions[] = [
                'id' => (string) $spigotPluginVersion['id'],
                'name' => $spigotPluginVersion['name'],
            ];
        }
        return $versions;
    }
    public function getDownloadUrl(string $pluginId, string $versionId): string
    {
        return 'https://api.spiget.org/v2/resources/' . $pluginId . '/versions/' . $versionId . '/download';
    }
}
