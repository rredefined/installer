<?php
namespace Pterodactyl\Services\Minecraft\Mods;
use GuzzleHttp\Client;
use Illuminate\Support\Facades\Cache;
use GuzzleHttp\Exception\TransferException;
use GuzzleHttp\Exception\BadResponseException;
class ModrinthModService
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
     * Search for mods on the provider.
     */
    public function search(string $searchQuery, int $pageSize, int $page, ?string $minecraftVersion = null, ?string $loader = null): array
    {
        try {
            $facets = [
                ["project_type:mod"],
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
                logger()->error('Received bad response when fetching mods.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [
                'data' => [],
                'total' => 0,
            ];
        }
        $mods = [];
        foreach ($response['hits'] as $modrinthMod) {
            $mods[] = [
                'id' => $modrinthMod['project_id'],
                'name' => $modrinthMod['title'],
                'description' => $modrinthMod['description'],
                'url' => 'https://modrinth.com/mod/' . $modrinthMod['slug'],
                'icon_url' => empty($modrinthMod['icon_url']) ? null : $modrinthMod['icon_url'],
            ];
        }
        return [
            'data' => $mods,
            'total' => $response['total_hits'],
        ];
    }
    /**
     * Get the versions of a specific mod for the provider.
     */
    public function versions(string $modId): array
    {
        $loaders = $this->getModLoaders();
        try {
            $response = json_decode($this->client->get('project/' . $modId . '/version', [
                'query' => [
                    'loaders' => json_encode($loaders),
                ],
            ])->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching mod versions.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [];
        }
        $versions = [];
        foreach ($response as $modrinthModVersion) {
            $versions[] = [
                'id' => $modrinthModVersion['id'],
                'name' => $modrinthModVersion['name'],
            ];
        }
        return $versions;
    }
    public function getDownloadUrl(string $modId, string $versionId): string
    {
        try {
            $response = json_decode($this->client->get('version/' . $versionId)->getBody(), true);
            return $response['files'][0]['url'];
        } catch (TransferException $e) {
            throw new \Exception('Failed to get download URL from Modrinth.');
        }
    }
    /**
     * Get available mod loaders.
     */
    public function getModLoaders(): array
    {
        return Cache::remember('modrinth-mod-loaders', 3600 * 24, function () {
            try {
                $response = json_decode($this->client->get('tag/loader')->getBody(), true);
                $modLoaders = [];
                foreach ($response as $loader) {
                    if (in_array('mod', $loader['supported_project_types'])) {
                        $modLoaders[] = $loader['name'];
                    }
                }
                return $modLoaders;
            } catch (TransferException $e) {
                return [];
            }
        });
    }
}
