<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\Mods;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Illuminate\Validation\Rule;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Models\Permission;
use Pterodactyl\Jobs\Server\Minecraft\Mods\InstallModJob;
use Illuminate\Auth\Access\AuthorizationException;
use Pterodactyl\Services\Minecraft\Mods\ModrinthModService;
use Pterodactyl\Services\Minecraft\Mods\CurseForgeModService;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
enum ModProvider: string
{
    case Modrinth = 'modrinth';
    case CurseForge = 'curseforge';
}
class ModController extends ClientApiController
{
    public function __construct(
        protected ModrinthModService $modrinthModService,
        protected CurseForgeModService $curseForgeModService
    ) {
        parent::__construct();
    }
    /**
     * List mods for a specific provider.
     */
    public function index(Request $request)
    {
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(ModProvider::class)],
            'page' => 'required|numeric|integer|min:1',
            'page_size' => 'required|numeric|integer|max:50',
            'search_query' => 'nullable|string',
            'minecraft_version' => 'nullable|string',
            'loader' => 'nullable|string',
        ]);
        $provider = ModProvider::from($validated['provider']);
        $page = (int) $validated['page'];
        $pageSize = (int) $validated['page_size'];
        $searchQuery = $validated['search_query'] ?? '';
        $minecraftVersion = $validated['minecraft_version'] ?? null;
        $loader = $validated['loader'] ?? null;
        $data = match ($provider) {
            ModProvider::Modrinth => $this->modrinthModService->search($searchQuery, $pageSize, $page, $minecraftVersion, $loader),
            ModProvider::CurseForge => $this->curseForgeModService->search($searchQuery, $pageSize, $page, $minecraftVersion),
        };
        $mods = $data['data'];
        return [
            'object' => 'list',
            'data' => $mods,
            'meta' => [
                'pagination' => [
                    'total' => $data['total'],
                    'count' => count($mods),
                    'per_page' => $pageSize,
                    'current_page' => $page,
                    'total_pages' => $data['total'] > 0 ? ceil($data['total'] / $pageSize) : 1,
                    'links' => [],
                ],
            ],
        ];
    }
    /**
     * List mod versions.
     */
    public function versions(Request $request, Server $server, string $modId)
    {
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(ModProvider::class)],
        ]);
        $provider = ModProvider::from($validated['provider']);
        $versions = match ($provider) {
            ModProvider::Modrinth => $this->modrinthModService->versions($modId),
            ModProvider::CurseForge => $this->curseForgeModService->versions($modId),
        };
        return [
             'object' => 'list',
             'data' => $versions
        ];
    }
    /**
     * Install a mod.
     */
    public function store(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_CREATE, $server)) {
            throw new AuthorizationException();
        }
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(ModProvider::class)],
            'mod_id' => 'required|string',
            'version_id' => 'required|string',
        ]);
        $provider = ModProvider::from($validated['provider']);
        $modId = $validated['mod_id'];
        $versionId = $validated['version_id'];
        InstallModJob::dispatch($server, $provider->value, $modId, $versionId);
        Activity::event('server:mod.install')
            ->subject($server)
            ->property('provider', $provider->value)
            ->property('mod_id', $modId)
            ->property('version_id', $versionId)
            ->log();
        return response()->noContent();
    }
}
