<?php
namespace Pterodactyl\Jobs\Server\Minecraft\Datapacks;
use Pterodactyl\Jobs\Job;
use Pterodactyl\Models\Server;
use Illuminate\Bus\Queueable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Services\Minecraft\Datapacks\VanillaTweaksService;
class InstallDatapackJob extends Job
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;
    public function __construct(
        public Server $server,
        public string $version,
        public string $type,
        public array $packs,
        public string $world
    ) {
    }
    public function handle(
        DaemonFileRepository $repository,
        VanillaTweaksService $service
    ) {
        $link = $service->generateDownloadLink($this->version, $this->type, $this->packs);
        if (!$link) {
            throw new \Exception('Failed to generate download link from VanillaTweaks.');
        }
        $zipContent = $service->downloadZip($link, $this->type);
        $repo = $repository->setServer($this->server);
        $targetDir = match($this->type) {
            'datapacks' => '/' . trim($this->world, '/') . '/datapacks',
            'craftingtweaks' => '/' . trim($this->world, '/') . '/datapacks',
            'resourcepacks' => '/resourcepacks', 
            default => '/'
        };
        try {
            if ($targetDir !== '/') {
                 $repo->createDirectory(basename($targetDir), dirname($targetDir) === '/' ? '/' : dirname($targetDir));
            }
        } catch (\Exception $e) {}
        $tempZipName = 'vt-install-' . uniqid() . '.zip';
        $repo->putContent($targetDir . '/' . $tempZipName, $zipContent);
        $repo->decompressFile($targetDir, $tempZipName);
        $repo->deleteFiles($targetDir, [$tempZipName]);
    }
}
