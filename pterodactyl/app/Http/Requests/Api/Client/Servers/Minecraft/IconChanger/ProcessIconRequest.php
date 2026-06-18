<?php
namespace Pterodactyl\Http\Requests\Api\Client\Servers\Minecraft\IconChanger;
use Pterodactyl\Http\Requests\Api\Client\ClientApiRequest;
class ProcessIconRequest extends ClientApiRequest
{
    /**
     * Rules to validate this request against.
     */
    public function rules(): array
    {
        return [
            'icon' => 'required|file|image|max:2048', 
        ];
    }
}
