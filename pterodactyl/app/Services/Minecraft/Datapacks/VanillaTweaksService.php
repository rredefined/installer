<?php
namespace Pterodactyl\Services\Minecraft\Datapacks;
use GuzzleHttp\Client;
use Illuminate\Support\Facades\Cache;
use GuzzleHttp\Exception\TransferException;
class VanillaTweaksService
{
    protected Client $client;
    protected string $userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0';
    public function __construct()
    {
        $this->client = new Client([
            'base_uri' => 'https://vanillatweaks.net',
            'headers' => [
                'User-Agent' => $this->userAgent,
                'Accept' => '*/*',
                'Accept-Language' => 'en-US,en;q=0.9',
            ],
            'timeout' => 30,
        ]);
    }
    public function getVersions(): array
    {
        return Cache::remember('vanillatweaks_versions', 3600, function () {
            try {
                $response = $this->client->get('/picker/datapacks/');
                $html = $response->getBody()->getContents();
                preg_match_all('/1\.\d+/', $html, $matches);
                $versions = array_unique($matches[0]);
                $validVersions = array_filter($versions, function ($v) {
                    return version_compare($v, '1.13', '>=') && version_compare($v, '2.0', '<');
                });
                usort($validVersions, fn($a, $b) => version_compare($b, $a));
                if (empty($validVersions)) {
                    return ['1.21', '1.20', '1.19', '1.18', '1.17', '1.16'];
                }
                return array_values($validVersions);
            } catch (\Exception $e) {
                return ['1.21', '1.20', '1.19', '1.18', '1.17', '1.16'];
            }
        });
    }
    public function getPacks(string $version, string $type = 'datapacks'): array
    {
        $prefixMap = [
            'datapacks' => 'dp',
            'resourcepacks' => 'rp',
            'craftingtweaks' => 'ct',
        ];
        $prefix = $prefixMap[$type] ?? 'dp';
        try {
            $response = $this->client->get('/assets/resources/json/' . $version . '/' . $prefix . 'categories.json', [
                'headers' => [
                    'Referer' => 'https://vanillatweaks.net/picker/' . $type . '/',
                ]
            ]);
            return json_decode($response->getBody()->getContents(), true) ?? [];
        } catch (TransferException $e) {
            logger()->error('Failed to fetch VanillaTweaks packs: ' . $e->getMessage());
            return [];
        }
    }
    public function generateDownloadLink(string $version, string $type, array $packs): ?string
    {
        $typeMap = [
            'datapacks' => 'datapacks',
            'resourcepacks' => 'resourcepacks',
            'craftingtweaks' => 'craftingtweaks',
        ];
        $fullType = $typeMap[$type] ?? 'datapacks';
        $packsFormatted = [];
        foreach ($packs as $category => $packList) {
            $categorySlug = strtolower(str_replace(['/', ' '], '-', $category));
            $packsFormatted[$categorySlug] = $packList;
        }
        $formData = 'version=' . urlencode($version) . '&packs=' . urlencode(json_encode($packsFormatted));
        try {
            $response = $this->client->post('/assets/server/zip' . $fullType . '.php', [
                'headers' => [
                    'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
                    'X-Requested-With' => 'XMLHttpRequest',
                    'Referer' => 'https://vanillatweaks.net/picker/' . $fullType . '/',
                ],
                'body' => $formData,
            ]);
            $result = json_decode($response->getBody()->getContents(), true);
            if (isset($result['status']) && $result['status'] === 'success') {
                return 'https://vanillatweaks.net' . $result['link'];
            }
        } catch (TransferException $e) {
            logger()->error('Failed to generate VanillaTweaks download link: ' . $e->getMessage());
        }
        return null;
    }
    public function downloadZip(string $url, string $type): string
    {
        usleep(rand(500000, 1500000));
        $response = $this->client->get($url, [
            'headers' => [
                'Referer' => 'https://vanillatweaks.net/picker/' . $type . '/',
            ]
        ]);
        return $response->getBody()->getContents();
    }
}
