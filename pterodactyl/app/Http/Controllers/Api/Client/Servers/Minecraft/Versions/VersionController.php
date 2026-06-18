<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\Versions;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Http;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Services\Servers\StartupModificationService;
use Pterodactyl\Repositories\Eloquent\ServerVariableRepository;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Repositories\Wings\DaemonPowerRepository;
class VersionController extends ClientApiController
{
    public function __construct(
        private ServerVariableRepository $repository,
        private StartupModificationService $startupModificationService
    ) {
        parent::__construct();
    }
    public function getMinecraftForks(Request $request, Server $server): array
    {
        $apiUrl = base64_decode('aHR0cHM6Ly9tY2phcnMuYXBwL2FwaS92Mi90eXBlcw==');
        $response = Http::get($apiUrl);
        if (!$response->successful()) {
            return [
                'success' => false,
                'error' => 'Failed to fetch Minecraft forks from API',
            ];
        }
        $data = $response->json();
        $forks = [];
        if (isset($data['success']) && $data['success'] && isset($data['types'])) {
            $allTypes = [];
            foreach (['recommended', 'established', 'experimental', 'miscellaneous', 'limbos'] as $category) {
                if (isset($data['types'][$category])) {
                    $allTypes = array_merge($allTypes, $data['types'][$category]);
                }
            }
            foreach ($allTypes as $typeId => $fork) {
                if (isset($fork['name']) && isset($fork['description'])) {
                    $totalBuilds = isset($fork['builds']) ? number_format($fork['builds']) : '?';
                    $totalVersions = isset($fork['versions']['minecraft']) ? number_format($fork['versions']['minecraft']) : '?';
                    $forks[$typeId] = [
                        'name' => $fork['name'],
                        'icon' => $fork['icon'] ?? null,
                        'description' => $fork['description'],
                        'builds' => $totalBuilds,
                        'versions' => ['minecraft' => $totalVersions]
                    ];
                }
            }
        }
        return [
            'success' => true,
            'forks' => $forks,
        ];
    }
    public function getVersions(Request $request, Server $server, string $type): array
    {
        $apiUrlBase = base64_decode('aHR0cHM6Ly9tY2phcnMuYXBwL2FwaS92Mi9idWlsZHMv');
        $response = Http::get($apiUrlBase . $type);
        if (!$response->successful()) {
            return [
                'success' => false,
                'error' => 'Failed to fetch versions from API',
            ];
        }
        $data = $response->json();
        $versions = [];
        if (isset($data['success']) && $data['success'] && isset($data['builds'])) {
            foreach ($data['builds'] as $versionId => $versionObj) {
                $versions[$versionId] = [
                    'type' => $versionObj['type'] ?? 'UNKNOWN',
                    'supported' => $versionObj['supported'] ?? true,
                    'builds' => $versionObj['builds'] ?? 0
                ];
            }
        }
        return [
            'success' => true,
            'versions' => $versions,
        ];
    }
    public function getBuilds(Request $request, Server $server, string $type, string $version): array
    {
        $apiUrlBase = base64_decode('aHR0cHM6Ly9tY2phcnMuYXBwL2FwaS92Mi9idWlsZHMv');
        $slash = base64_decode('Lw==');
        $response = Http::get($apiUrlBase . $type . $slash . $version);
        if (!$response->successful()) {
            return [
                'success' => false,
                'error' => 'Failed to fetch builds from API',
            ];
        }
        $data = $response->json();
        $builds = [];
        if (isset($data['success']) && $data['success'] && isset($data['builds'])) {
            foreach ($data['builds'] as $buildObj) {
                if (isset($buildObj['buildNumber'])) {
                    $buildNumber = (string)$buildObj['buildNumber'];
                    $buildName = isset($buildObj['name']) ? $buildObj['name'] : "Build {$buildNumber}";
                    $builds[] = [
                        'buildNumber' => $buildNumber,
                        'name' => $buildName,
                        'time' => isset($buildObj['created']) ? $buildObj['created'] : date('Y-m-d H:i:s'),
                        'channel' => $buildObj['experimental'] ? 'EXPERIMENTAL' : 'STABLE',
                        'changes' => $buildObj['changes'] ?? []
                    ];
                }
            }
        }
        usort($builds, function ($a, $b) {
            return $b['buildNumber'] <=> $a['buildNumber'];
        });
        return [
            'success' => true,
            'builds' => $builds,
        ];
    }
    public function updateMinecraftVersion(Request $request, Server $server): array
    {
        $this->validate($request, [
            'type' => 'required|string',
            'version' => 'required|string',
            'build' => 'required|string',
            'buildName' => 'string',
            'deleteFiles' => 'boolean',
            'acceptEula' => 'boolean',
        ]);
        $type = $request->input('type');
        $version = $request->input('version');
        $build = $request->input('build');
        $deleteFiles = $request->input('deleteFiles', false);
        $acceptEula = $request->input('acceptEula', false);
        $buildName = $request->input('buildName', $build);
        Log::info('Minecraft Version Change Request', [
            'server_id' => $server->id,
            'type' => $type,
            'version' => $version,
            'build' => $build,
            'deleteFiles' => $deleteFiles,
            'acceptEula' => $acceptEula,
        ]);
        $buildsApiBase = base64_decode('aHR0cHM6Ly9tY2phcnMuYXBwL2FwaS92Mi9idWlsZHMv');
        $slash = base64_decode('Lw==');
        $buildsUrl = $buildsApiBase . $type . $slash . $version;
        $response = Http::get($buildsUrl);
        if (!$response->successful()) {
            Log::error('Failed to fetch builds from API', [
                'status' => $response->status(),
                'body' => $response->body(),
                'url' => $buildsUrl
            ]);
            return [
                'success' => false,
                'error' => 'Failed to fetch builds from API: ' . $response->status(),
            ];
        }
        $buildsData = $response->json();
        Log::info('Builds data response', ['data' => $buildsData]);
        $downloadUrl = null;
        $actualBuildName = null;
        $isZipFile = false;
        $selectedBuild = null;
        $specialTypes = ['FABRIC', 'FORGE', 'NEOFORGE', 'SPONGE', 'LEGACYFABRIC'];
        $isSpecialType = in_array(strtoupper($type), $specialTypes);
        if (isset($buildsData['success']) && $buildsData['success'] && isset($buildsData['builds'])) {
            foreach ($buildsData['builds'] as $buildInfo) {
                if ($isSpecialType) {
                    if (isset($buildInfo['name']) && $buildInfo['name'] === $build) {
                        $selectedBuild = $buildInfo;
                        break;
                    }
                } else {
                    if (isset($buildInfo['buildNumber']) && (string)$buildInfo['buildNumber'] === $build) {
                        $selectedBuild = $buildInfo;
                        break;
                    }
                }
            }
            if (!$selectedBuild && $build === 'latest' && !empty($buildsData['builds'])) {
                $selectedBuild = $buildsData['builds'][0];
            }
        }
        if ($selectedBuild) {
            if (isset($selectedBuild['zipUrl']) && !empty($selectedBuild['zipUrl'])) {
                $downloadUrl = $selectedBuild['zipUrl'];
                $isZipFile = true;
            } elseif (isset($selectedBuild['jarUrl']) && !empty($selectedBuild['jarUrl'])) {
                $downloadUrl = $selectedBuild['jarUrl'];
            }
            $actualBuildName = isset($selectedBuild['name']) ? $selectedBuild['name'] : "Build {$build}";
        }
        if (!$downloadUrl) {
            Log::error('Download URL not found', [
                'selectedBuild' => $selectedBuild ?? 'Not found',
                'isSpecialType' => $isSpecialType,
                'build' => $build
            ]);
            return [
                'success' => false,
                'error' => 'Download URL not found for the selected build',
            ];
        }
        if (!filter_var($downloadUrl, FILTER_VALIDATE_URL)) {
            Log::error('Invalid download URL', ['url' => $downloadUrl]);
            return [
                'success' => false,
                'error' => 'Invalid download URL format',
            ];
        }
        Log::info('Download URL found', [
            'url' => $downloadUrl,
            'isZipFile' => $isZipFile,
            'buildName' => $actualBuildName,
        ]);
        $finalBuildName = $actualBuildName ?: $buildName;
        $fileRepository = app()->make(DaemonFileRepository::class);
        $powerRepository = app()->make(DaemonPowerRepository::class);
        try {
            $powerRepository->setServer($server)->send('kill');
            Log::info('Server killed successfully');
        } catch (\Exception $e) {
            Log::warning('Failed to kill server', ['error' => $e->getMessage()]);
        }
        if ($deleteFiles) {
            try {
                $files = $fileRepository->setServer($server)->getDirectory('/');
                if (count($files) > 0) {
                    $fileRepository->setServer($server)->deleteFiles(
                        '/',
                        collect($files)->map(fn ($file) => $file['name'])->toArray()
                    );
                    Log::info('Deleted all server files');
                }
            } catch (\Exception $e) {
                Log::warning('Failed to delete server files', ['error' => $e->getMessage()]);
            }
        }
        if (!$deleteFiles) {
            try {
                $fileRepository->setServer($server)->deleteFiles('/', ['libraries']);
                Log::info('Deleted libraries folder');
            } catch (\Exception $e) {
                Log::warning('Failed to delete libraries folder', ['error' => $e->getMessage()]);
            }
        }
        $filename = $isZipFile ? 'server.zip' : 'server.jar';
        if ($type === 'FABRIC') {
            try {
                Log::info("Downloading Fabric server from URL: " . $downloadUrl);
                $response = $server->client()->request('POST', '/api/servers/' . $server->uuid . '/files/pull', [
                    'json' => [
                        'url' => $downloadUrl,
                        'directory' => '/',
                        'filename' => $filename,
                        'use_header' => true,
                        'foreground' => true,
                    ],
                ]);
                $statusCode = $response->getStatusCode();
                if ($statusCode !== 204) {
                    Log::error("Failed to download Fabric server via Wings API. Status Code: " . $statusCode);
                    return [
                        'success' => false,
                        'error' => "Failed to download Fabric server. Status Code: " . $statusCode,
                    ];
                }
                Log::info("Successfully downloaded Fabric server via Wings API");
            } catch (\Exception $e) {
                Log::error("Exception while downloading Fabric server: " . $e->getMessage());
                try {
                    Log::info("Trying alternative method with curl for Fabric download");
                    $ch = curl_init($downloadUrl);
                    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
                    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
                    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
                    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36');
                    $fabricJar = curl_exec($ch);
                    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                    $error = curl_error($ch);
                    curl_close($ch);
                    if ($httpCode !== 200 || empty($fabricJar)) {
                        Log::error("Failed to download Fabric server. HTTP Code: " . $httpCode . ", Error: " . $error);
                        return [
                            'success' => false,
                            'error' => "Failed to download Fabric server. HTTP Code: " . $httpCode . ", Error: " . $error,
                        ];
                    }
                    Log::info("Successfully downloaded Fabric server, size: " . strlen($fabricJar) . " bytes");
                    $fileRepository->setServer($server)->putContent('/' . $filename, $fabricJar);
                    Log::info("Uploaded Fabric server to game server as: " . $filename);
                } catch (\Exception $e2) {
                    Log::error("Exception in alternative method: " . $e2->getMessage());
                    return [
                        'success' => false,
                        'error' => 'Failed to download Fabric server: ' . $e2->getMessage(),
                    ];
                }
            }
        } else {
            try {
                Log::info("Downloading server from URL: " . $downloadUrl);
                $fileRepository->setServer($server)->pull($downloadUrl, '/', [
                    'filename' => $filename,
                    'foreground' => true,
                ]);
                Log::info("Successfully downloaded server");
            } catch (\Exception $e) {
                Log::error("Failed to download server: " . $e->getMessage());
                return [
                    'success' => false,
                    'error' => 'Failed to download server: ' . $e->getMessage(),
                ];
            }
        }
        if ($isZipFile) {
            try {
                Log::info("Decompressing zip file: " . $filename);
                $fileRepository->setServer($server)->decompressFile('/', $filename);
                try {
                    $fileRepository->setServer($server)->deleteFiles('/', [$filename]);
                    Log::info("Deleted zip file after extraction");
                } catch (\Exception $e) {
                    Log::warning("Failed to delete zip file after extraction: " . $e->getMessage());
                }
                Log::info("Successfully decompressed zip file");
            } catch (\Exception $e) {
                Log::error("Failed to extract zip file: " . $e->getMessage());
                return [
                    'success' => false,
                    'error' => 'Failed to extract zip file: ' . $e->getMessage(),
                ];
            }
        }
        if ($acceptEula) {
            try {
                Log::info("Creating eula.txt file");
                $fileRepository->setServer($server)->putContent('/eula.txt', "eula=true");
                Log::info("Successfully created eula.txt");
            } catch (\Exception $e) {
                Log::warning("Failed to create eula.txt: " . $e->getMessage());
            }
        }
        $variable = $server->variables()->where('env_variable', 'SERVER_JARFILE')->first();
        if ($variable) {
            try {
                Log::info("Updating SERVER_JARFILE variable to server.jar");
                $this->repository->updateOrCreate([
                    'server_id' => $server->id,
                    'variable_id' => $variable->id,
                ], [
                    'variable_value' => 'server.jar',
                ]);
                Log::info("Successfully updated SERVER_JARFILE variable");
            } catch (\Exception $e) {
                Log::warning("Failed to update SERVER_JARFILE variable: " . $e->getMessage());
            }
        }
        Log::info("Updating server metadata with new Minecraft version info", [
            'type' => $type,
            'version' => $version,
            'build' => $finalBuildName,
        ]);
        $server->update([
            'minecraft_type' => $type,
            'minecraft_version' => $version,
            'minecraft_build' => $finalBuildName,
        ]);
        Log::info("Minecraft version change completed successfully");
        return [
            'success' => true,
        ];
    }
    public function getCurrentVersion(Request $request, Server $server): array
    {
        if ($server->minecraft_type && $server->minecraft_version && $server->minecraft_build) {
            return [
                'success' => true,
                'current' => [
                    'type' => $server->minecraft_type,
                    'version' => $server->minecraft_version,
                    'build' => $server->minecraft_build,
                ],
            ];
        }
        $detectedVersion = $this->detectMinecraftVersion($server);
        if ($detectedVersion) {
            $server->minecraft_type = $detectedVersion['type'];
            $server->minecraft_version = $detectedVersion['version'];
            $server->minecraft_build = $detectedVersion['build'];
            $server->save();
            return [
                'success' => true,
                'current' => $detectedVersion,
            ];
        }
        return [
            'success' => true,
            'warning' => true,
            'message' => 'Please select one of the Minecraft forks below to install the version you want.',
            'current' => [
                'type' => 'VANILLA',
                'version' => '1.20.4',
                'build' => 'latest',
            ],
        ];
    }
    private function detectMinecraftVersion(Server $server): ?array
    {
        $fileRepository = app()->make(DaemonFileRepository::class);
        try {
            $versionJson = $fileRepository->setServer($server)->getContent('/version.json');
            if ($versionJson) {
                $versionData = json_decode($versionJson, true);
                if (isset($versionData['name'])) {
                    return [
                        'type' => 'VANILLA',
                        'version' => $versionData['name'],
                        'build' => 'latest',
                    ];
                }
            }
        } catch (\Exception $e) {
        }
        try {
            $serverProperties = $fileRepository->setServer($server)->getContent('/server.properties');
            if ($serverProperties) {
                $lines = explode("\n", $serverProperties);
                foreach ($lines as $line) {
                    if (strpos($line, 'motd=') === 0) {
                        $motd = substr($line, 5);
                        if (preg_match('/(\d+\.\d+(\.\d+)?)/', $motd, $matches)) {
                            return [
                                'type' => 'UNKNOWN',
                                'version' => $matches[1],
                                'build' => 'unknown',
                            ];
                        }
                    }
                }
            }
        } catch (\Exception $e) {
        }
        try {
            $files = $fileRepository->setServer($server)->getDirectory('/');
            $jarFiles = array_filter($files, function ($file) {
                return isset($file['mimetype']) && $file['mimetype'] === 'application/java-archive';
            });
            foreach ($jarFiles as $file) {
                $filename = strtolower($file['name']);
                if (strpos($filename, 'paper') !== false) {
                    if (preg_match('/(\d+\.\d+(\.\d+)?)/', $filename, $matches)) {
                        return [
                            'type' => 'PAPER',
                            'version' => $matches[1],
                            'build' => 'unknown',
                        ];
                    }
                    return [
                        'type' => 'PAPER',
                        'version' => 'unknown',
                        'build' => 'unknown',
                    ];
                }
                if (strpos($filename, 'spigot') !== false) {
                    if (preg_match('/(\d+\.\d+(\.\d+)?)/', $filename, $matches)) {
                        return [
                            'type' => 'SPIGOT',
                            'version' => $matches[1],
                            'build' => 'unknown',
                        ];
                    }
                    return [
                        'type' => 'SPIGOT',
                        'version' => 'unknown',
                        'build' => 'unknown',
                    ];
                }
                if (strpos($filename, 'forge') !== false) {
                    if (preg_match('/(\d+\.\d+(\.\d+)?)/', $filename, $matches)) {
                        return [
                            'type' => 'FORGE',
                            'version' => $matches[1],
                            'build' => 'unknown',
                        ];
                    }
                    return [
                        'type' => 'FORGE',
                        'version' => 'unknown',
                        'build' => 'unknown',
                    ];
                }
                if (strpos($filename, 'fabric') !== false) {
                    if (preg_match('/(\d+\.\d+(\.\d+)?)/', $filename, $matches)) {
                        return [
                            'type' => 'FABRIC',
                            'version' => $matches[1],
                            'build' => 'unknown',
                        ];
                    }
                    return [
                        'type' => 'FABRIC',
                        'version' => 'unknown',
                        'build' => 'unknown',
                    ];
                }
            }
        } catch (\Exception $e) {
        }
        return null;
    }
}
