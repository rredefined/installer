<?php
namespace Pterodactyl\Jobs\Server\Minecraft\Worlds;
use Pterodactyl\Jobs\Job;
use Pterodactyl\Models\Server;
use Illuminate\Bus\Queueable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Collection;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Services\Minecraft\Worlds\CurseForgeWorldService;
use Pterodactyl\Facades\Activity;
class InstallWorldJob extends Job
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;
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
    public $timeout = 600;
    public string $jobIdentifier;
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
     * Decompress the downloaded world file
     */
    private function decompressWorldFile(DaemonFileRepository $repository, string $filename): void
    {
        $maxWaitTime = 120; 
        $waitInterval = 3; 
        $elapsedTime = 0;
        while ($elapsedTime < $maxWaitTime) {
            try {
                $files = $repository->setServer($this->server)->getDirectory('/');
                $worldFile = collect($files)->firstWhere('name', $filename);
                if ($worldFile && $worldFile['size'] > 0) {
                    try {
                        $repository->setServer($this->server)->decompressFile('/', $filename);
                        $repository->setServer($this->server)->deleteFiles('/', [$filename]);
                        return;
                    } catch (\Exception $decompressError) {
                        try {
                            $repository->setServer($this->server)->deleteFiles('/', [$filename]);
                        } catch (\Exception $deleteError) {
                            return;
                        }
                        return;
                    }
                }
            } catch (\Exception $e) {
                return;
            }
            sleep($waitInterval);
            $elapsedTime += $waitInterval;
        }
    }
    public function __construct(
        public Server $server,
        public string $worldId,
        public string $versionId
    ) {
        $this->jobIdentifier = 'world_' . uniqid();
    }
    public function getJobIdentifier(): string
    {
        return $this->jobIdentifier;
    }
    /**
     * Execute the job.
     *
     * @param  \Pterodactyl\Repositories\Wings\DaemonFileRepository  $repository
     * @param  \Pterodactyl\Services\Minecraft\Worlds\CurseForgeWorldService  $service
     * @return void
     *
     * @throws \Throwable
     */
    public function handle(
        DaemonFileRepository $repository,
        CurseForgeWorldService $service
    ) {
        try {
            $downloadParams = $service->getDownloadUrl($this->worldId, $this->versionId);
            $filename = $downloadParams['filename'];
            $repository->setServer($this->server);
            $realUrl = $this->returnFinalRedirect($downloadParams['url']);
            \Cache::put("world_download:{$this->jobIdentifier}", [
                'download_id' => $this->jobIdentifier,
                'filename' => $filename,
                'server_id' => $this->server->id,
                'status' => 'downloading'
            ], 3600);
            $response = $repository->pull(
                $realUrl,
                '/',
                [
                    'filename' => $filename,
                    'use_header' => false,
                    'foreground' => true  
                ]
            );
            sleep(2);
            try {
                $files = $repository->setServer($this->server)->getDirectory('/');
                $worldFile = collect($files)->firstWhere('name', $filename);
                if ($worldFile && $worldFile['size'] > 0) {
                    $repository->setServer($this->server)->decompressFile('/', $filename);
                    $repository->setServer($this->server)->deleteFiles('/', [$filename]);
                    \Cache::put("world_download:{$this->jobIdentifier}", [
                        'download_id' => $this->jobIdentifier,
                        'filename' => $filename,
                        'server_id' => $this->server->id,
                        'status' => 'completed',
                        'decompressed' => true
                    ], 3600);
                }
            } catch (\Exception $decompressError) {
                try {
                    $repository->setServer($this->server)->deleteFiles('/', [$filename]);
                } catch (\Exception $deleteError) {
                }
                \Cache::put("world_download:{$this->jobIdentifier}", [
                    'download_id' => $this->jobIdentifier,
                    'filename' => $filename,
                    'server_id' => $this->server->id,
                    'status' => 'failed',
                    'error' => 'Decompression failed'
                ], 3600);
            }
        } catch (\Exception $e) {
            \Cache::put("world_download:{$this->jobIdentifier}", [
                'download_id' => $this->jobIdentifier,
                'filename' => $filename ?? 'unknown',
                'server_id' => $this->server->id,
                'status' => 'failed',
                'error' => 'Download failed'
            ], 3600);
            return;
        }
    }
}
