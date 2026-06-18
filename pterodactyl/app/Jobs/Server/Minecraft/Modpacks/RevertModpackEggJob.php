<?php
namespace Pterodactyl\Jobs;
use Pterodactyl\Models\Server;
use Illuminate\Bus\Queueable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Support\Facades\Log;
class RevertModpackEggJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;
    /**
     * The number of times the job may be attempted.
     *
     * @var int
     */
    public $tries = 120; 
    /**
     * The number of seconds to wait before retrying the job.
     *
     * @var int
     */
    public $backoff = 10;
    /**
     * Create a new job instance.
     */
    public function __construct(
        public int $serverId,
        public int $originalEggId,
        public string $originalStartup,
        public string $originalImage
    ) {
    }
    /**
     * Execute the job.
     */
    public function handle()
    {
        $server = Server::find($this->serverId);
        if (!$server) {
            return;
        }
        if ($server->status === Server::STATUS_INSTALLING) {
            $this->release(10);
            return;
        }
        Log::info("Modpack installation finished for server {$server->id}. Reverting to original configuration.");
        $server->egg_id = $this->originalEggId;
        $server->startup = $this->originalStartup;
        $server->image = $this->originalImage;
        $server->save();
    }
}
