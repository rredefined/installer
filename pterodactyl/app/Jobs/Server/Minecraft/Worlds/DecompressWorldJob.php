<?php
namespace Pterodactyl\Jobs\Server\Minecraft\Worlds;
use Pterodactyl\Jobs\Job;
use Pterodactyl\Models\Server;
use Illuminate\Bus\Queueable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Support\Facades\Log;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
class DecompressWorldJob extends Job
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;
    /**
     * The number of times the job may be attempted.
     *
     * @var int
     */
    public $tries = 3;
    /**
     * The number of seconds the job can run before timing out.
     *
     * @var int
     */
    public $timeout = 300;
    /**
     * Create a new job instance.
     */
    public function __construct(
        public Server $server,
        public string $filename,
        public string $downloadId
    ) {
    }
    /**
     * Execute the job.
     *
     * @param  \Pterodactyl\Repositories\Wings\DaemonFileRepository  $repository
     * @return void
     */
    public function handle(DaemonFileRepository $repository)
    {
        $maxWaitTime = 120; 
        $waitInterval = 3; 
        $elapsedTime = 0;
        Log::info("Starting decompression job for world file: {$this->filename} on server {$this->server->id}");
        while ($elapsedTime < $maxWaitTime) {
            try {
                $files = $repository->setServer($this->server)->getDirectory('/');
                $worldFile = collect($files)->firstWhere('name', $this->filename);
                if ($worldFile && $worldFile['size'] > 0) {
                    Log::info("World file found, size: {$worldFile['size']} bytes, starting decompression");
                    try {
                        $repository->setServer($this->server)->decompressFile('/', $this->filename);
                        $repository->setServer($this->server)->deleteFiles('/', [$this->filename]);
                        \Cache::put("world_download:{$this->downloadId}", [
                            'status' => 'completed',
                            'filename' => $this->filename,
                            'server_id' => $this->server->id,
                            'decompressed' => true
                        ], 3600);
                        Log::info("World file {$this->filename} decompressed successfully");
                        return;
                    } catch (\Exception $decompressError) {
                        Log::error("Failed to decompress world file: " . $decompressError->getMessage());
                        try {
                            $repository->setServer($this->server)->deleteFiles('/', [$this->filename]);
                        } catch (\Exception $deleteError) {
                            Log::error("Failed to delete corrupted world file: " . $deleteError->getMessage());
                        }
                        \Cache::put("world_download:{$this->downloadId}", [
                            'status' => 'failed',
                            'filename' => $this->filename,
                            'server_id' => $this->server->id,
                            'error' => 'Decompression failed'
                        ], 3600);
                        return;
                    }
                }
            } catch (\Exception $e) {
                Log::error("Error checking for world file: " . $e->getMessage());
                return;
            }
            sleep($waitInterval);
            $elapsedTime += $waitInterval;
        }
        Log::warning("Timeout waiting for world file {$this->filename} to become available");
        \Cache::put("world_download:{$this->downloadId}", [
            'status' => 'timeout',
            'filename' => $this->filename,
            'server_id' => $this->server->id,
            'error' => 'File download timeout'
        ], 3600);
    }
}
