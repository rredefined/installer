<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\Worlds;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Illuminate\Validation\Rule;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Models\Permission;
use Pterodactyl\Jobs\Server\Minecraft\Worlds\InstallWorldJob;
use Illuminate\Auth\Access\AuthorizationException;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Services\Minecraft\Worlds\CurseForgeWorldService;
enum WorldProvider: string
{
    case CurseForge = 'curseforge';
}
class WorldController extends ClientApiController
{
    public function __construct(
        protected CurseForgeWorldService $curseForgeWorldService,
        protected DaemonFileRepository $fileRepository
    ) {
        parent::__construct();
    }
    /**
     * Follow redirects to get the final URL
     */
    private function returnFinalRedirect(string $url, int $max = 5, int $used = 0, string|null $prev = null): string
    {
        if ($used >= $max) {
            return $url;
        }
        if (str_starts_with($url, '/')) {
            $host = parse_url($prev, PHP_URL_HOST);
            if (!$host) {
                throw new \Exception('Failed to determine host.');
            }
            $url = sprintf('%s://%s%s', parse_url($prev, PHP_URL_SCHEME), $host, $url);
        }
        $response = get_headers($url, true);
        if (!$response) {
            throw new \Exception('Failed to query URL.');
        }
        $response = array_change_key_case($response, CASE_LOWER);
        if (array_key_exists('location', $response)) {
            try {
                if (is_array($response['location'])) {
                    return $this->returnFinalRedirect($response['location'][count($response['location']) - 1], $max, $used + 1, $url);
                } else {
                    return $this->returnFinalRedirect($response['location'], $max, $used + 1, $url);
                }
            } catch (\Throwable $e) {
                return $url;
            }
        }
        return $url;
    }
    /**
     * List worlds for a specific provider.
     */
    public function index(Request $request)
    {
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(WorldProvider::class)],
            'page' => 'required|numeric|integer|min:1',
            'page_size' => 'required|numeric|integer|max:50',
            'search_query' => 'nullable|string',
        ]);
        $provider = WorldProvider::from($validated['provider']);
        $page = (int) $validated['page'];
        $pageSize = (int) $validated['page_size'];
        $searchQuery = $validated['search_query'] ?? '';
        $data = match ($provider) {
            WorldProvider::CurseForge => $this->curseForgeWorldService->search($searchQuery, $pageSize, $page),
        };
        $worlds = $data['data'];
        return [
            'object' => 'list',
            'data' => $worlds,
            'meta' => [
                'pagination' => [
                    'total' => $data['total'],
                    'count' => count($worlds),
                    'per_page' => $pageSize,
                    'current_page' => $page,
                    'total_pages' => $data['total'] > 0 ? ceil($data['total'] / $pageSize) : 1,
                    'links' => [],
                ],
            ],
        ];
    }
    /**
     * List installed worlds on the server.
     */
    public function installed(Request $request, Server $server)
    {
        $this->fileRepository->setServer($server);
        try {
            $files = $this->fileRepository->getDirectory('/');
        } catch (\Exception $e) {
            return [
                'object' => 'list',
                'data' => [],
                'meta' => ['active_world' => 'unknown'],
            ];
        }
        $blacklist = [
            'libraries', 'versions', 'logs', 'crash-reports', 'plugins', 'mods', 'config', 'cache', 'bundler', 'web', 
            '.fabric', 'debug', 'webeditor', '.mixin.out'
        ];
        $directories = collect($files)
            ->filter(function ($file) use ($blacklist) {
                return $file['mime'] === 'inode/directory' && !in_array($file['name'], $blacklist) && !str_starts_with($file['name'], '.');
            });
        $worlds = [];
        foreach ($directories as $dir) {
            try {
                $subFiles = $this->fileRepository->getDirectory('/' . $dir['name']);
                $hasLevelDat = collect($subFiles)->contains('name', 'level.dat');
                if ($hasLevelDat) {
                    $worlds[] = ['name' => $dir['name']];
                }
            } catch (\Exception $e) {
                continue;
            }
        }
        $activeWorld = 'world';
        try {
            $content = $this->fileRepository->getContent('server.properties');
            if (preg_match('/^level-name=(.*)$/m', $content, $matches)) {
                $activeWorld = trim($matches[1]);
            }
        } catch (\Exception $e) {
        }
        return [
            'object' => 'list',
            'data' => $worlds,
            'meta' => [
                'active_world' => $activeWorld,
            ]
        ];
    }
    /**
     * Delete an installed world.
     */
    public function deleteWorld(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_DELETE, $server)) {
            throw new AuthorizationException();
        }
        $validated = $request->validate([
            'name' => 'required|string',
        ]);
        $this->fileRepository->setServer($server);
        $this->fileRepository->deleteFiles('/', [$validated['name']]);
        Activity::event('server:world.delete')
            ->subject($server)
            ->property('name', $validated['name'])
            ->log();
        return response()->noContent();
    }
    /**
     * Set a world as active (default).
     */
    public function setActiveWorld(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_UPDATE, $server)) {
            throw new AuthorizationException();
        }
        $validated = $request->validate([
            'name' => 'required|string',
        ]);
        $this->fileRepository->setServer($server);
        try {
            $content = $this->fileRepository->getContent('server.properties');
            if (preg_match('/^level-name=.*$/m', $content)) {
                $newContent = preg_replace('/^level-name=.*$/m', 'level-name=' . $validated['name'], $content);
            } else {
                $newContent = $content . "\nlevel-name=" . $validated['name'];
            }
            $this->fileRepository->putContent('server.properties', $newContent);
            Activity::event('server:world.set_active')
                ->subject($server)
                ->property('name', $validated['name'])
                ->log();
        } catch (\Exception $e) {
            throw new \Exception('Failed to update server.properties');
        }
        return response()->noContent();
    }
    /**
     * List world versions.
     */
    public function versions(Request $request, Server $server, string $worldId)
    {
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(WorldProvider::class)],
        ]);
        $provider = WorldProvider::from($validated['provider']);
        $versions = match ($provider) {
            WorldProvider::CurseForge => $this->curseForgeWorldService->versions($worldId),
        };
        return [
             'object' => 'list',
             'data' => $versions
        ];
    }
    /**
     * Install a world.
     */
    public function store(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_CREATE, $server)) {
            throw new AuthorizationException();
        }
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(WorldProvider::class)],
            'world_id' => 'required|string',
            'version_id' => 'required|string',
        ]);
        $provider = WorldProvider::from($validated['provider']);
        $worldId = $validated['world_id'];
        $versionId = $validated['version_id'];
        $job = new InstallWorldJob($server, $worldId, $versionId);
        $jobId = $job->getJobIdentifier();
        dispatch($job);
        Activity::event('server:world.install')
            ->subject($server)
            ->property('provider', $provider->value)
            ->property('world_id', $worldId)
            ->property('version_id', $versionId)
            ->log();
        return response()->json([
            'download_id' => $jobId,
            'message' => 'World download started'
        ]);
    }
    /**
     * Check world download status.
     */
    public function downloadStatus(Request $request, Server $server, string $downloadId)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_READ, $server)) {
            throw new AuthorizationException();
        }
        $cachedData = \Cache::get("world_download:{$downloadId}");
        if (!$cachedData) {
            return response()->json([
                'status' => 'not_found',
                'message' => 'Download not found or expired'
            ], 404);
        }
        return response()->json([
            'status' => $cachedData['status'] ?? 'unknown',
            'filename' => $cachedData['filename'] ?? 'unknown',
            'download_id' => $cachedData['download_id'] ?? $downloadId,
            'decompressed' => $cachedData['decompressed'] ?? false,
            'error' => $cachedData['error'] ?? null
        ]);
    }
    /**
     * Query world file information.
     */
    public function queryFile(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_READ, $server)) {
            throw new AuthorizationException();
        }
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(WorldProvider::class)],
            'world_id' => 'required|string',
            'version_id' => 'required|string',
        ]);
        $provider = WorldProvider::from($validated['provider']);
        $worldId = $validated['world_id'];
        $versionId = $validated['version_id'];
        $downloadParams = match ($provider) {
            WorldProvider::CurseForge => $this->curseForgeWorldService->getDownloadUrl($worldId, $versionId),
        };
        $url = $downloadParams['url'];
        $data = \Cache::remember("worlds:queryUrl:$url", 60, function () use ($url, $downloadParams) {
            $realUrl = $this->returnFinalRedirect($url);
            $response = get_headers($realUrl, true);
            if (!$response) {
                throw new \Exception('Failed to query URL.');
            }
            $response = array_change_key_case($response, CASE_LOWER);
            $contentDisposition = array_key_exists('content-disposition', $response) ? $response['content-disposition'] : null;
            $filename = $downloadParams['filename'];
            if ($contentDisposition) {
                $matches = [];
                preg_match('/filename(\*)?=(UTF-8\'\')?"?([^";]+)"?;?/', $contentDisposition, $matches);
                if (count($matches) > 2) {
                    $filename = iconv_mime_decode($matches[3]);
                }
            }
            $size = array_key_exists('content-length', $response) ? (int) $response['content-length'] : null;
            if ($size <= 1024) {
                throw new \Exception('Failed to determine file size. Make sure the url is a direct link to the file.');
            }
            return [
                'filename' => $filename,
                'size' => $size,
            ];
        });
        if (!$data['filename']) {
            $data['filename'] = basename($url);
        }
        return response()->json($data);
    }
}
