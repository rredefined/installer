<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\IconChanger;
use Carbon\CarbonImmutable;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Server;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Services\Nodes\NodeJWTService;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\Icons\GetUploadUrlRequest;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Intervention\Image\ImageManager;
use Intervention\Image\Drivers\Gd\Driver;
use Illuminate\Support\Facades\Log;
class IconChangerController extends ClientApiController
{
    /**
     * IconChangerController constructor.
     */
    public function __construct(
        private NodeJWTService $jwtService,
        private DaemonFileRepository $fileRepository
    ) {
        parent::__construct();
    }
    /**
     * Returns a signed URL that allows for the upload of a server icon.
     */
    public function __invoke(GetUploadUrlRequest $request, Server $server): JsonResponse
    {
        return new JsonResponse([
            'object' => 'signed_url',
            'attributes' => [
                'url' => $this->getUploadUrl($server, $request->user()),
            ],
        ]);
    }
    /**
     * Returns a URL where the server icon can be uploaded to.
     */
    protected function getUploadUrl(Server $server, User $user): string
    {
        $token = $this->jwtService
            ->setExpiresAt(CarbonImmutable::now()->addMinutes(15))
            ->setUser($user)
            ->setClaims([
                'server_uuid' => $server->uuid,
                'icon_upload' => true,
            ])
            ->handle($server->node, $user->id . $server->uuid);
        return sprintf(
            '%s/upload/icon?token=%s',
            $server->node->getConnectionAddress(),
            $token->toString()
        );
    }
}
