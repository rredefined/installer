<?php
namespace Pterodactyl\Jobs\Server\Minecraft\Modpacks;
use Pterodactyl\Jobs\Job;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Server;
use Illuminate\Queue\SerializesModels;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Repositories\Wings\DaemonPowerRepository;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Servers\ReinstallServerService;
use Pterodactyl\Services\Servers\StartupModificationService;
class InstallModpackJob extends Job implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use SerializesModels;
    /**
     * The number of times the job may be attempted.
     *
     * @var int
     */
    public $tries = 1;
    /**
     * The number of seconds the job can run before timing out.
     *
     * @var int
     */
    public $timeout = 1800; 
    /**
     * Create a new job instance.
     */
    public function __construct(
        public Server $server,
        public string $provider,
        public string $modpackId,
        public string $modpackVersionId,
        public bool $deleteServerFiles,
    ) {
    }
    /**
     * Execute the job.
     */
    public function handle(
        StartupModificationService $startupModificationService,
        DaemonFileRepository $fileRepository,
        ReinstallServerService $reinstallServerService,
        DaemonPowerRepository $daemonPowerRepository,
        DaemonServerRepository $daemonServerRepository,
    ): void {
        $daemonPowerRepository->setServer($this->server)->send('kill');
        $daemonServerRepository->setServer($this->server);
        $attempts = 0;
        while ($daemonServerRepository->getDetails()['state'] !== 'offline' && $attempts < 60) {
            sleep(1);
            $attempts++;
        }
        if ($this->deleteServerFiles) {
            $fileRepository->setServer($this->server);
            try {
                $filesToDelete = collect(
                    $fileRepository->getDirectory('/')
                )->pluck('name')->toArray();
                if (count($filesToDelete) > 0) {
                    $fileRepository->deleteFiles('/', $filesToDelete);
                }
            } catch (\Exception $e) {
            }
        }
        $currentEgg = $this->server->egg;
        $installerEgg = Egg::where('author', 'obscure404@pterodactyl.io')->firstOrFail();
        $startupModificationService->setUserLevel(User::USER_LEVEL_ADMIN);
        rescue(function () use ($startupModificationService, $installerEgg, $reinstallServerService) {
            $startupModificationService->handle($this->server, [
                'nest_id' => $installerEgg->nest_id,
                'egg_id' => $installerEgg->id,
            ]);
            $startupModificationService->handle($this->server, [
                'environment' => [
                    'MODPACK_PROVIDER' => $this->provider,
                    'MODPACK_ID' => $this->modpackId,
                    'MODPACK_VERSION_ID' => $this->modpackVersionId,
                    'DELETE_SERVER_FILES' => $this->deleteServerFiles ? '1' : '0',
                    'CURSEFORGE_API_KEY' => config('services.curseforge.api_key', ''),
                ],
            ]);
            $reinstallServerService->handle($this->server);
        });
        sleep(10); 
        $startupModificationService->handle($this->server, [
            'nest_id' => $currentEgg->nest_id,
            'egg_id' => $currentEgg->id,
        ]);
    }
    protected function getImageForJavaVersion(array $availableImages, string $javaVersion): ?string
    {
        if (function_exists('array_find')) {
            return array_find($availableImages, fn ($v, $k) => str_ends_with($k, ' ' . $javaVersion));
        }
        foreach ($availableImages as $name => $avImage) {
            if (str_ends_with($name, ' ' . $javaVersion)) {
                return $avImage;
            }
        }
        return null;
    }
}
