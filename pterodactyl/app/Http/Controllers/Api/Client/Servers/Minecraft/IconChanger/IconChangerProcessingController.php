<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Models\Server;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\Minecraft\IconChanger\ProcessIconRequest;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Intervention\Image\ImageManager;
use Intervention\Image\Drivers\Gd\Driver;
use Illuminate\Support\Facades\Log;
class IconChangerProcessingController extends ClientApiController
{
    /**
     * IconChangerProcessingController constructor.
     */
    public function __construct(
        private DaemonFileRepository $fileRepository
    ) {
        parent::__construct();
    }
    /**
     * Processes the uploaded server icon.
     */
    public function __invoke(ProcessIconRequest $request, Server $server): JsonResponse
    {
        try {
            $file = $request->file('icon');
            $manager = new ImageManager(new Driver());
            $image = $manager->read($file->getRealPath());
            $image->cover(64, 64);
            $imageContents = $image->toPng();
            $this->fileRepository->setServer($server)->putContent('server-icon.png', $imageContents);
            return new JsonResponse([
                'success' => true,
                'message' => 'Server icon has been updated successfully.',
            ]);
        } catch (\Exception $exception) {
            Log::error($exception);
            return new JsonResponse([
                'success' => false,
                'message' => 'An error occurred while processing the server icon: ' . $exception->getMessage(),
            ], 500);
        }
    }
}
