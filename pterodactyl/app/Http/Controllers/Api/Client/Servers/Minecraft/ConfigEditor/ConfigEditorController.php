<?php
namespace Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\ConfigEditor;
use GuzzleHttp\Promise\Utils;
use Pterodactyl\Models\Server;
use Symfony\Component\Yaml\Yaml;
use Pterodactyl\Facades\Activity;
use Illuminate\Http\Request;
use GuzzleHttp\Promise\PromiseInterface;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\ConfigEditor\Dependencies\Yosymfony\Toml\Toml;
use Pterodactyl\Http\Controllers\Api\Client\Servers\Minecraft\ConfigEditor\Dependencies\Yosymfony\Toml\TomlBuilder;
class ConfigEditorController extends ClientApiController
{
    public function __construct(
        private DaemonFileRepository $fileRepository,
    ) {
        parent::__construct();
    }
    private function compactKeys(array $array): array
    {
        $result = [];
        foreach ($array as $key => $value) {
            if (is_array($value)) {
                foreach ($this->compactKeys($value) as $subKey => $subValue) {
                    $result["{$key}.{$subKey}"] = $subValue;
                }
            } else {
                $result[$key] = $value;
            }
        }
        return $result;
    }
    private function expandKeys(array $array): array
    {
        $result = [];
        foreach ($array as $key => $value) {
            $parts = explode('.', $key);
            $ref = &$result;
            foreach ($parts as $part) {
                if (!isset($ref[$part])) {
                    $ref[$part] = [];
                }
                $ref = &$ref[$part];
            }
            $ref = $value;
        }
        return $result;
    }
    private function configs(): array
    {
        return [
            ['file' => 'server.properties', 'type' => 'VANILLA', 'format' => 'PROPERTIES'],
            ['file' => 'spigot.yml', 'type' => 'SPIGOT', 'format' => 'YAML'],
            ['file' => 'bukkit.yml', 'type' => 'SPIGOT', 'format' => 'YAML'],
            ['file' => 'paper.yml', 'type' => 'PAPER', 'format' => 'YAML'],
            ['file' => 'config/paper-global.yml', 'type' => 'PAPER', 'format' => 'YAML'],
            ['file' => 'config/paper-world-defaults.yml', 'type' => 'PAPER', 'format' => 'YAML'],
            ['file' => 'pufferfish.yml', 'type' => 'PUFFERFISH', 'format' => 'YAML'],
            ['file' => 'purpur.yml', 'type' => 'PURPUR', 'format' => 'YAML'],
            ['file' => 'leaves.yml', 'type' => 'LEAVES', 'format' => 'YAML'],
            ['file' => 'canvas.yml', 'type' => 'CANVAS', 'format' => 'YAML'],
            ['file' => 'config/canvas-server.json5', 'type' => 'CANVAS', 'format' => 'JSON5'],
            ['file' => 'divinemc.yml', 'type' => 'DIVINEMC', 'format' => 'YAML'],
            ['file' => 'config/sponge/global.conf', 'type' => 'SPONGE', 'format' => 'CONF'],
            ['file' => 'config/sponge/sponge.conf', 'type' => 'SPONGE', 'format' => 'CONF'],
            ['file' => 'config/sponge/tracker.conf', 'type' => 'SPONGE', 'format' => 'CONF'],
            ['file' => 'arclight.conf', 'type' => 'ARCLIGHT', 'format' => 'CONF'],
            ['file' => 'config/neoforge-server.toml', 'type' => 'NEOFORGE', 'format' => 'TOML'],
            ['file' => 'config/neoforge-common.toml', 'type' => 'NEOFORGE', 'format' => 'TOML'],
            ['file' => 'mohist-config/mohist.yml', 'type' => 'MOHIST', 'format' => 'YAML'],
            ['file' => 'velocity.toml', 'type' => 'VELOCITY', 'format' => 'TOML'],
            ['file' => 'config.yml', 'type' => 'BUNGEECORD', 'format' => 'YAML'],
            ['file' => 'waterfall.yml', 'type' => 'WATERFALL', 'format' => 'YAML'],
            ['file' => 'settings.yml', 'type' => 'NANOLIMBO', 'format' => 'YAML'],
            ['file' => 'magma.yml', 'type' => 'MAGMA', 'format' => 'YAML'],
            ['file' => 'config/leaf-global.yml', 'type' => 'LEAF', 'format' => 'YAML'],
            ['file' => 'config/gale-global.yml', 'type' => 'LEAF', 'format' => 'YAML'],
            ['file' => 'config/gale-world-defaults.yml', 'type' => 'LEAF', 'format' => 'YAML'],
        ];
    }
    private function getServerConfig(Server $server, string $file): PromiseInterface
    {
        return $this->fileRepository->setServer($server)->getHttpClient()->getAsync(
            sprintf('/api/servers/%s/files/contents', $server->uuid),
            [
                'query' => ['file' => $file],
            ]
        );
    }
    private function parseServerConfig(string $format, string|null $content): array|null
    {
        if (!$content) {
            return null;
        }
        try {
            switch ($format) {
                case "PROPERTIES":
                    $lines = explode("\n", $content);
                    $result = [];
                    foreach ($lines as $line) {
                        if (empty($line) || $line[0] === '#') {
                            continue;
                        }
                        $parts = explode('=', $line, 2);
                        $result[$parts[0]] = $parts[1] ?? '';
                    }
                    return $this->compactKeys($result);
                case "YAML":
                    return $this->compactKeys(Yaml::parse($content));
                case "TOML":
                    return $this->compactKeys(Toml::parse($content));
            }
            return [];
        } catch (\Throwable $e) {
            return [];
        }
    }
    private function stringifyServerConfig(string $format, array $content): string|null
    {
        if (!$content) {
            return null;
        }
        switch ($format) {
            case "PROPERTIES":
                $result = [];
                foreach ($this->compactKeys($content) as $key => $value) {
                    $value = is_bool($value)
                        ? ($value ? 'true' : 'false')
                        : $value;
                    $result[] = is_array($value)
                        ? "{$key}="
                        : "{$key}={$value}";
                }
                return implode("\n", $result);
            case "YAML":
                return Yaml::dump($content, 10);
            case "TOML":
                $builder = new TomlBuilder();
                uksort($content, fn($a, $b) => is_array($a) <=> is_array($b));
                foreach ($content as $key => $value) {
                    if (is_array($value)) {
                        $builder->addTable($key);
                        foreach ($value as $subKey => $subValue) {
                            $builder->addValue($subKey, $subValue ?? '');
                        }
                    } else {
                        $builder->addValue($key, $value ?? '');
                    }
                }
                return $builder->getTomlString();
        }
        return null;
    }
    public function index(Request $request, Server $server): array
    {
        $configs = $this->configs();
        $promises = [];
        try {
            $files = array_map(fn($file) => $file['name'], $this->fileRepository->setServer($server)->getDirectory('/'));
        } catch (\Exception $e) {
             $files = [];
        }
        foreach ($configs as $config) {
            if (!in_array($config['file'], $files) && !str_contains($config['file'], '/')) {
                $promises[$config['file']] = null;
                continue;
            }
            $promises[$config['file']] = $this->getServerConfig($server, $config['file']);
        }
        $values = Utils::settle($promises)->wait();
        return [
            'success' => true,
            'configs' => array_map(fn($config) => [
                ...$config,
                'content' => $values[$config['file']]['state'] === 'fulfilled'
                    ? $this->parseServerConfig($config['format'], $values[$config['file']]['value']?->getBody()?->__toString())
                    : null,
                'raw' => $values[$config['file']]['state'] === 'fulfilled'
                    ? $values[$config['file']]['value']?->getBody()?->__toString()
                    : null,
            ], $configs),
        ];
    }
    public function save(Request $request, Server $server): array
    {
        $data = $request->validate([
            'file' => 'required|string',
            'contents' => 'nullable|array',
            'raw_content' => 'nullable|string',
        ]);
        $configs = $this->configs();
        $format = null;
        foreach ($configs as $config) {
            if ($config['file'] === $data['file']) {
                $format = $config['format'];
                break;
            }
        }
        if (!$format) {
            return [
                'success' => false,
                'error' => 'Invalid file',
            ];
        }
        if (isset($data['raw_content'])) {
            $content = $data['raw_content'];
        } else {
            $content = $this->stringifyServerConfig($format, $this->expandKeys($data['contents']));
        }
        if (is_null($content)) {
            return [
                'success' => false,
                'error' => 'Invalid format',
            ];
        }
        $this->fileRepository->setServer($server)->putContent($data['file'], $content);
        Activity::event('server:config.save')
            ->subject($server)
            ->property('config', $data['file'])
            ->log('Updated server configuration file via Config Editor');
        return ['success' => true];
    }
}
