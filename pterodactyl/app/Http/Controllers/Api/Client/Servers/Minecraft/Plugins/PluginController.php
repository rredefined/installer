<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\Plugins;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Illuminate\Validation\Rule;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Models\Permission;
use Pterodactyl\Jobs\Server\Minecraft\Plugins\InstallPluginJob;
use Illuminate\Auth\Access\AuthorizationException;
use Pterodactyl\Services\Minecraft\Plugins\ModrinthPluginService;
use Pterodactyl\Services\Minecraft\Plugins\CurseForgePluginService;
use Pterodactyl\Services\Minecraft\Plugins\SpigotMCPluginService;
use Pterodactyl\Services\Minecraft\Plugins\HangarPluginService;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
enum PluginProvider: string
{
    case Modrinth = 'modrinth';
    case CurseForge = 'curseforge';
    case SpigotMC = 'spigotmc';
    case Hangar = 'hangar';
}
class PluginController extends ClientApiController
{
    public function __construct(
        protected ModrinthPluginService $modrinthPluginService,
        protected CurseForgePluginService $curseForgePluginService,
        protected SpigotMCPluginService $spigotMCPluginService,
        protected HangarPluginService $hangarPluginService
    ) {
        parent::__construct();
    }
    /**
     * List plugins for a specific provider.
     */
    public function index(Request $request)
    {
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(PluginProvider::class)],
            'page' => 'required|numeric|integer|min:1',
            'page_size' => 'required|numeric|integer|max:50',
            'search_query' => 'nullable|string',
            'minecraft_version' => 'nullable|string',
            'loader' => 'nullable|string',
        ]);
        $provider = PluginProvider::from($validated['provider']);
        $page = (int) $validated['page'];
        $pageSize = (int) $validated['page_size'];
        $searchQuery = $validated['search_query'] ?? '';
        $minecraftVersion = $validated['minecraft_version'] ?? null;
        $loader = $validated['loader'] ?? null;
        $data = match ($provider) {
            PluginProvider::Modrinth => $this->modrinthPluginService->search($searchQuery, $pageSize, $page, $minecraftVersion, $loader),
            PluginProvider::CurseForge => $this->curseForgePluginService->search($searchQuery, $pageSize, $page, $minecraftVersion),
            PluginProvider::SpigotMC => $this->spigotMCPluginService->search($searchQuery, $pageSize, $page, $minecraftVersion),
            PluginProvider::Hangar => $this->hangarPluginService->search($searchQuery, $pageSize, $page, $minecraftVersion),
        };
        $plugins = $data['data'];
        return [
            'object' => 'list',
            'data' => $plugins,
            'meta' => [
                'pagination' => [
                    'total' => $data['total'],
                    'count' => count($plugins),
                    'per_page' => $pageSize,
                    'current_page' => $page,
                    'total_pages' => $data['total'] > 0 ? ceil($data['total'] / $pageSize) : 1,
                    'links' => [],
                ],
            ],
        ];
    }
    /**
     * List plugin versions.
     */
    public function versions(Request $request, Server $server, string $pluginId)
    {
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(PluginProvider::class)],
        ]);
        $provider = PluginProvider::from($validated['provider']);
        $versions = match ($provider) {
            PluginProvider::Modrinth => $this->modrinthPluginService->versions($pluginId),
            PluginProvider::CurseForge => $this->curseForgePluginService->versions($pluginId),
            PluginProvider::SpigotMC => $this->spigotMCPluginService->versions($pluginId),
            PluginProvider::Hangar => $this->hangarPluginService->versions($pluginId),
        };
        return [
             'object' => 'list',
             'data' => $versions
        ];
    }
    /**
     * Install a plugin.
     */
    public function store(Request $request, Server $server)
    {
        if (!$request->user()->can(Permission::ACTION_FILE_CREATE, $server)) {
            throw new AuthorizationException();
        }
        $validated = $request->validate([
            'provider' => ['required', Rule::enum(PluginProvider::class)],
            'plugin_id' => 'required|string',
            'version_id' => 'required|string',
        ]);
        $provider = PluginProvider::from($validated['provider']);
        $pluginId = $validated['plugin_id'];
        $versionId = $validated['version_id'];
        InstallPluginJob::dispatch($server, $provider->value, $pluginId, $versionId);
        Activity::event('server:plugin.install')
            ->subject($server)
            ->property('provider', $provider->value)
            ->property('plugin_id', $pluginId)
            ->property('version_id', $versionId)
            ->log();
        return response()->noContent();
    }
}
