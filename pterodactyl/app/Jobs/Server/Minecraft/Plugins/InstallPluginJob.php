<?php
namespace Pterodactyl\Jobs\Server\Minecraft\Plugins;
use Pterodactyl\Jobs\Job;
use Pterodactyl\Models\Server;
use Illuminate\Bus\Queueable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Container\Container;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Services\Minecraft\Plugins\ModrinthPluginService;
use Pterodactyl\Services\Minecraft\Plugins\CurseForgePluginService;
use Pterodactyl\Services\Minecraft\Plugins\SpigotMCPluginService;
use Pterodactyl\Services\Minecraft\Plugins\HangarPluginService;
use Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\Plugins\PluginProvider;
class InstallPluginJob extends Job
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;
    /**
     * InstallPluginJob constructor.
     */
    public function __construct(
        public Server $server,
        public string $provider,
        public string $pluginId,
        public string $versionId
    ) {
    }
    /**
     * Run the job.
     */
    public function handle(
        DaemonFileRepository $repository,
        ModrinthPluginService $modrinth,
        CurseForgePluginService $curseforge,
        SpigotMCPluginService $spigot,
        HangarPluginService $hangar
    ) {
        $providerEnum = PluginProvider::from($this->provider);
        $service = match ($providerEnum) {
            PluginProvider::Modrinth => $modrinth,
            PluginProvider::CurseForge => $curseforge,
            PluginProvider::SpigotMC => $spigot,
            PluginProvider::Hangar => $hangar,
        };
        $url = $service->getDownloadUrl($this->pluginId, $this->versionId);
        try {
            $repository->setServer($this->server)->createDirectory('plugins', '/');
        } catch (\Exception $e) {
        }
        $repository->setServer($this->server)->pull(
            $url,
            '/plugins'
        );
    }
}
