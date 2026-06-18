<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\Datapacks;
use GuzzleHttp\Client;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Permission;
use Illuminate\Auth\Access\AuthorizationException;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Services\Minecraft\Datapacks\VanillaTweaksService;
use Pterodactyl\Jobs\Server\Minecraft\Datapacks\InstallDatapackJob;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
class DatapackController extends ClientApiController
{
    public function __construct(
        protected VanillaTweaksService $service,
        protected DaemonFileRepository $fileRepository
    ) {
        parent::__construct();
    }
    public function index(Request $request, Server $server)
    {
        $version = $request->query('version', '1.21');
        $type = $request->query('type', 'datapacks');
        return $this->service->getPacks($version, $type);
    }
    public function getVersions(Request $request)
    {
        return $this->service->getVersions();
    }
    public function detectVersion(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_READ, $server)) {
            throw new AuthorizationException();
        }
        $this->fileRepository->setServer($server);
        try {
            $contents = $this->fileRepository->getDirectory('/versions');
            foreach ($contents as $item) {
                if (preg_match('/^(\d+\.\d+)/', $item['name'], $matches)) {
                    return ['version' => $matches[1]];
                }
            }
        } catch (\Exception $e) {
        }
        return ['version' => null];
    }
    public function worlds(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_READ, $server)) {
            throw new AuthorizationException();
        }
        $this->fileRepository->setServer($server);
        $worlds = [];
        try {
            $contents = $this->fileRepository->getDirectory('/');
            foreach ($contents as $item) {
                if (!$item['is_file']) {
                    try {
                        $sub = $this->fileRepository->getDirectory('/' . $item['name']);
                        foreach ($sub as $subItem) {
                            if ($subItem['name'] === 'datapacks') {
                                $worlds[] = ['name' => $item['name']];
                                break;
                            }
                        }
                    } catch (\Exception $e) {
                        continue;
                    }
                }
            }
        } catch (\Exception $e) {
        }
        return $worlds;
    }
    public function install(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_CREATE, $server)) {
            throw new AuthorizationException();
        }
        $validated = $request->validate([
            'version' => 'required|string',
            'packs' => 'required|array',
            'world' => 'required_if:type,datapacks|string|nullable',
            'type' => 'required|string|in:datapacks,resourcepacks,craftingtweaks',
        ]);
        InstallDatapackJob::dispatch(
            $server,
            $validated['version'],
            $validated['type'],
            $validated['packs'],
            $validated['world'] ?? 'world'
        );
        return response()->noContent();
    }
    public function image(Request $request)
    {
        $version = $request->query('version', '1.21');
        $type = $request->query('type', 'datapacks');
        $pack = $request->query('pack');
        if (!$pack) {
            return response()->json(['error' => 'Pack required'], 400);
        }
        $prefix = match($type) {
            'resourcepacks' => 'resourcepacks',
            'craftingtweaks' => 'craftingtweaks',
            default => 'datapacks',
        };
        $url = 'https://vanillatweaks.net/assets/resources/icons/' . $prefix . '/' . $version . '/' . rawurlencode($pack) . '.png';
        $client = new Client();
        try {
            $response = $client->get($url, [
                'headers' => ['User-Agent' => 'Mozilla/5.0']
            ]);
            return response($response->getBody()->getContents())
                ->header('Content-Type', 'image/png')
                ->header('Cache-Control', 'public, max-age=86400');
        } catch (\Exception $e) {
            return response()->json(['error' => 'Image not found'], 404);
        }
    }
}
