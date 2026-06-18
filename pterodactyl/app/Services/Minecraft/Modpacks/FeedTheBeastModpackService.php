<?php
namespace Pterodactyl\Services\Minecraft\Modpacks;
use GuzzleHttp\Pool;
use GuzzleHttp\Client;
use GuzzleHttp\Psr7\Request;
use GuzzleHttp\Psr7\Response;
use GuzzleHttp\Exception\TransferException;
use GuzzleHttp\Exception\BadResponseException;
class FeedTheBeastModpackService
{
    protected Client $client;
    protected string $userAgent = 'Pterodactyl Panel/v2 (https://pterodactyl.io)';
    public function __construct()
    {
        $this->client = new Client([
            'base_uri' => 'https://api.feed-the-beast.com/v1/modpacks/public/modpack/',
            'headers' => [
                'User-Agent' => $this->userAgent,
            ],
        ]);
    }
    /**
     * Search for modpacks on the provider.
     */
    public function search(string $searchQuery, int $pageSize, int $page): array
    {
        $uri = (empty($searchQuery) ? 'popular/installs/' : 'search/') . '10000';
        try {
            $response = json_decode($this->client->get($uri, [
                'query' => [
                    'term' => $searchQuery,
                ],
            ])->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching modpacks.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [
                'data' => [],
                'total' => 0,
            ];
        }
        if (!isset($response['packs'])) {
            return [
                'data' => [],
                'total' => 0,
            ];
        }
        $allPacks = $response['packs'];
        $total = count($allPacks);
        $pagedPacks = array_slice($allPacks, ($page - 1) * $pageSize, $pageSize);
        $requests = [];
        foreach ($pagedPacks as $feedthebeastPackId) {
            if ($feedthebeastPackId == 81) { 
                continue;
            }
            $requests[] = new Request('GET', (string) $feedthebeastPackId);
        }
        $modpacks = [];
        $pool = new Pool($this->client, $requests, [
            'concurrency' => 5,
            'fulfilled' => function (Response $response, $index) use (&$modpacks) {
                if ($response->getStatusCode() != 200) {
                    logger()->error('Received bad response when fetching modpacks.', ['response' => \GuzzleHttp\Psr7\Message::toString($response)]);
                    return;
                }
                $feedthebeastModpack = json_decode($response->getBody(), true);
                if ($feedthebeastModpack['status'] === 'error') {
                    logger()->error('Received bad response when fetching modpacks.', ['response' => \GuzzleHttp\Psr7\Message::toString($response)]);
                    return;
                }
                $iconUrl = array_values(array_filter($feedthebeastModpack['art'], function ($art) {
                    return $art['type'] === 'square';
                }))[0]['url'];
                $modpacks[$index] = [
                    'id' => (string) $feedthebeastModpack['id'],
                    'name' => $feedthebeastModpack['name'],
                    'description' => $feedthebeastModpack['description'],
                    'url' => 'https://feed-the-beast.com/modpacks/' . $feedthebeastModpack['id'],
                    'icon_url' => $iconUrl,
                ];
            },
        ]);
        $pool->promise()->wait();
        ksort($modpacks);
        $modpacks = array_values($modpacks);
        return [
            'data' => $modpacks,
            'total' => $total,
        ];
    }
    /**
     * Get the versions of a specific modpack for the provider.
     */
    public function versions(string $modpackId): array
    {
        try {
            $response = json_decode($this->client->get($modpackId)->getBody(), true);
        } catch (TransferException $e) {
            if ($e instanceof BadResponseException) {
                logger()->error('Received bad response when fetching modpack versions.', ['response' => \GuzzleHttp\Psr7\Message::toString($e->getResponse())]);
            }
            return [];
        }
        $versions = [];
        foreach ($response['versions'] as $feedthebeastModpackVersion) {
            $versions[] = [
                'id' => (string) $feedthebeastModpackVersion['id'],
                'name' => $feedthebeastModpackVersion['name'],
            ];
        }
        $versions = array_reverse($versions);
        return $versions;
    }
}
