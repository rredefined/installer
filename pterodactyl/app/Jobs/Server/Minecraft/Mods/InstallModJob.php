<?php
namespace Pterodactyl\Jobs\Server\Minecraft\Mods;
use Pterodactyl\Jobs\Job;
use Pterodactyl\Models\Server;
use Illuminate\Bus\Queueable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Services\Minecraft\Mods\ModrinthModService;
use Pterodactyl\Services\Minecraft\Mods\CurseForgeModService;
use Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\Mods\ModProvider;
class InstallModJob extends Job
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;
    /**
     * InstallModJob constructor.
     */
    public function __construct(
        public Server $server,
        public string $provider,
        public string $modId,
        public string $versionId
    ) {
    }
    /**
     * Run the job.
     */
    public function handle(
        DaemonFileRepository $repository,
        ModrinthModService $modrinth,
        CurseForgeModService $curseforge
    ) {
        $providerEnum = ModProvider::from($this->provider);
        $service = match ($providerEnum) {
            ModProvider::Modrinth => $modrinth,
            ModProvider::CurseForge => $curseforge,
        };
        $url = $service->getDownloadUrl($this->modId, $this->versionId);
        try {
            $repository->setServer($this->server)->createDirectory('mods', '/');
        } catch (\Exception $e) {
        }
        $repository->setServer($this->server)->pull(
            $url,
            '/mods'
        );
    }
}
