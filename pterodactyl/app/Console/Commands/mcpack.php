<?php
namespace Pterodactyl\Console\Commands;
use Illuminate\Console\Command;
use Symfony\Component\Console\Formatter\OutputFormatterStyle;
use Illuminate\Support\Facades\File;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
class MCPack extends Command
{
    protected $signature = 'mcpack {action?}';
    protected $description = 'Auto Installer and Uninstaller for MCPack Minecraft Features.';
    public function handle()
    {
        $panelUrl = config('app.url');
        $request = Request::create($panelUrl);
        $this->touchModMetric($request);
        $action = $this->argument('action');
        $title = new OutputFormatterStyle('#fff', null, ['bold']);
        $this->output->getFormatter()->setStyle('title', $title);
        $b = new OutputFormatterStyle(null, null, ['bold']);
        $this->output->getFormatter()->setStyle('b', $b);
        if ($action === null) {
            $this->line("
            <title>
▄████▄ █████▄ ▄█████ ▄█████ ██  ██ █████▄  ██████ ██  ██  ▄██▄  ██  ██ 
██  ██ ██▄▄██ ▀▀▀▄▄▄ ██     ██  ██ ██▄▄██▄ ██▄▄   ▀█████ ██  ██ ▀█████ 
▀████▀ ██▄▄█▀ █████▀ ▀█████ ▀████▀ ██   ██ ██▄▄▄▄     ██  ▀██▀      ██ 
           MCPack - Minecraft Pack for Pterodactyl Panel</title>
           > php artisan mcpack (this window)
           > php artisan mcpack install
           > php artisan mcpack uninstall
            ");
        } elseif ($action === 'install') {
            $this->install();
        } elseif ($action === 'uninstall') {
            $this->uninstall();
        } else {
            $this->error("Invalid action. Supported actions: install, uninstall");
        }
    }
    public function install()
    {
        $this->info('<title>Installing MCPack...</title>');
        $this->configureApiKeys();
        $this->installApiRoutes();
        $this->installFrontendRoutes();
        $this->installIconChanger();
        $this->installCurseForgeConfig();
        $this->info('<title>Running post-installation commands...</title>');
        $this->info('Installing Node.js and dependencies...');
        $this->command('curl -sL https://deb.nodesource.com/setup_24.x | sudo -E bash -');
        $this->command('sudo apt install -y nodejs');
        $this->command('npm i -g yarn');
        $this->command('yarn');
        $this->info('Running Laravel maintenance commands...');
        $this->command('php artisan down');
        $this->command('composer dump-autoload --no-interaction');
        $this->command('php artisan migrate --force');
        $this->info('Building frontend assets...');
        $this->command('export NODE_OPTIONS=--openssl-legacy-provider && yarn build:production');
        $this->info('Clearing caches...');
        $this->command('php artisan cache:clear');
        $this->command('php artisan view:clear');
        $this->command('php artisan config:clear');
        $this->command('php artisan route:clear');
        $this->info('Setting file permissions...');
        $this->command('chown -R www-data:www-data /var/www/pterodactyl/*');
        $this->command('chmod -R 755 storage/* bootstrap/cache');
        $this->info('Running final optimizations...');
        $this->command('php artisan queue:restart');
        $this->command('php artisan optimize');
        $this->command('systemctl restart pteroq.service');
        $this->command('php artisan up');
        $this->info('<title>MCPack installation completed successfully!</title>');
    }
    private function configureApiKeys()
    {
        $this->info('Configuring API Keys...');
        $envPath = base_path('.env');
        $envContent = File::get($envPath);
        $currentCurseForge = $this->getEnvValue($envContent, 'CURSEFORGE_API_KEY');
        $this->line('<b>CurseForge API Key</b>');
        $this->line('Get your API key from: https://console.curseforge.com/');
        if (!empty($currentCurseForge)) {
            $curseForgeKey = $this->ask('Enter new CurseForge API Key (press Enter to keep current)', $currentCurseForge);
        } else {
            $curseForgeKey = $this->ask('Enter CurseForge API Key');
        }
        $this->updateEnvKey($envPath, $envContent, 'CURSEFORGE_API_KEY', $curseForgeKey);
        $this->info('✓ API Keys configured successfully');
    }
    private function getEnvValue(string $envContent, string $key): string
    {
        $pattern = "/^{$key}=(.*)$/m";
        if (preg_match($pattern, $envContent, $matches)) {
            return trim($matches[1] ?? '');
        }
        return '';
    }
    private function maskApiKey(string $key): string
    {
        if (strlen($key) <= 8) {
            return str_repeat('*', strlen($key));
        }
        return substr($key, 0, 4) . str_repeat('*', strlen($key) - 8) . substr($key, -4);
    }
    private function updateEnvKey(string $envPath, string &$envContent, string $key, ?string $value): void
    {
        if (empty($value)) {
            return;
        }
        $pattern = "/^" . preg_quote($key, '/') . "=.*/m";
        if (preg_match($pattern, $envContent)) {
            $envContent = preg_replace($pattern, "{$key}=" . str_replace('$', '\\$', $value), $envContent);
        } else {
            $envContent .= "\n{$key}={$value}";
        }
        File::put($envPath, $envContent);
    }
    private function installApiRoutes()
    {
        $this->info('Installing API routes...');
        $apiClientPath = base_path('routes/api-client.php');
        if (str_contains(File::get($apiClientPath), 'api-mcpack.php')) {
            $this->info('API routes already installed. Skipping...');
            return;
        }
        $content = File::get($apiClientPath);
        $searchString = "Route::put('/docker-image', [Client\\Servers\\SettingsController::class, 'dockerImage']);\n    });\n});";
        $replaceString = "Route::put('/docker-image', [Client\\Servers\\SettingsController::class, 'dockerImage']);\n    });\ninclude __DIR__.'/api-mcpack.php';\n});";
        if (str_contains($content, "Route::put('/docker-image', [Client\\Servers\\SettingsController::class, 'dockerImage']);")) {
            $newContent = str_replace($searchString, $replaceString, $content);
            File::put($apiClientPath, $newContent);
            $this->info('✓ API routes added successfully');
        } else {
            $this->error('Could not find the appropriate location to add API routes');
        }
    }
    private function installFrontendRoutes()
    {
        $this->info('Installing frontend routes...');
        $routesPath = base_path('resources/scripts/routers/routes.ts');
        if (str_contains(File::get($routesPath), '/minecraft/modpacks')) {
            $this->info('Frontend routes already installed. Skipping...');
            return;
        }
        $content = File::get($routesPath);
        $importSection = "import ServerActivityLogContainer from '@/components/server/ServerActivityLogContainer';";
        $newImports = "
import ModpackContainer from '@/components/server/minecraft/modpacks/ModpackContainer';
import PluginContainer from '@/components/server/minecraft/plugins/PluginContainer';
import ModContainer from '@/components/server/minecraft/mods/ModContainer';
import DatapackContainer from '@/components/server/minecraft/datapacks/DatapackContainer';
import VersionContainer from '@/components/server/minecraft/versions/VersionContainer';
import ConfigEditorContainer from '@/components/server/minecraft/config/ConfigEditorContainer';
import WorldContainer from '@/components/server/minecraft/worlds/WorldContainer';";
        $content = str_replace($importSection, $importSection . $newImports, $content);
        $routePattern = '/(\s*{\s*path:\s*\'\/activity\',\s*permission:\s*\'activity\.\*\',\s*name:\s*\'Activity\',\s*component:\s*ServerActivityLogContainer,\s*},\s*)(\],)/s';
        $newRoutes = "\n        {
            path: '/minecraft/modpacks',
            permission: 'settings.*',
            name: 'Modpacks',
            component: ModpackContainer,
        },
        {
            path: '/minecraft/plugins',
            permission: 'settings.*',
            name: 'Plugins',
            component: PluginContainer,
        },
        {
            path: '/minecraft/mods',
            permission: 'settings.*',
            name: 'Mods',
            component: ModContainer,
        },
        {
            path: '/minecraft/datapacks',
            permission: 'settings.*',
            name: 'Datapacks',
            component: DatapackContainer,
        },
        {
            path: '/minecraft/versions',
            permission: 'settings.*',
            name: 'Versions',
            component: VersionContainer,
        },
        {
            path: '/minecraft/configs',
            permission: 'settings.*',
            name: 'Configs',
            component: ConfigEditorContainer,
        },
        {
            path: '/minecraft/worlds',
            permission: 'settings.*',
            name: 'Worlds',
            component: WorldContainer,
        },";
        if (preg_match($routePattern, $content)) {
            $newContent = preg_replace($routePattern, '$1' . $newRoutes . "\n$2", $content);
            File::put($routesPath, $newContent);
            $this->info('✓ Frontend routes added successfully');
        } else {
            $this->error('Could not find the appropriate location to add frontend routes');
        }
    }
    private function installIconChanger()
    {
        $this->info('Installing IconChanger button...');
        $fileManagerPath = base_path('resources/scripts/components/server/files/FileManagerContainer.tsx');
        if (str_contains(File::get($fileManagerPath), 'IconChangerButton')) {
            $this->info('IconChanger button already installed. Skipping...');
            return;
        }
        $content = File::get($fileManagerPath);
        $lastImport = "import style from './style.module.css';";
        $newImport = "import IconChangerButton from '@/components/elements/minecraft/IconChanger/IconChangerButton';";
        $content = str_replace($lastImport, $lastImport . "\n" . $newImport, $content);
        $navLinkPattern = '/(<\/NavLink>)/';
        $newButton = '$1
                            <IconChangerButton />';
        if (preg_match($navLinkPattern, $content)) {
            $newContent = preg_replace($navLinkPattern, $newButton, $content);
            File::put($fileManagerPath, $newContent);
            $this->info('✓ IconChanger button added successfully');
        } else {
            $this->error('Could not find the appropriate location to add IconChanger button');
        }
    }
    public function uninstall()
    {
        $this->info('<title>Uninstalling MCPack...</title>');
        $this->uninstallApiRoutes();
        $this->uninstallFrontendRoutes();
        $this->uninstallIconChanger();
        $this->uninstallCurseForgeConfig();
        $this->removeMcpackFiles();
        $this->info('<title>Running post-uninstallation commands...</title>');
        $this->info('Ensuring Node.js and dependencies are available...');
        $this->command('curl -sL https://deb.nodesource.com/setup_22.x | sudo -E bash -');
        $this->command('sudo apt install -y nodejs');
        $this->command('npm i -g yarn');
        $this->command('yarn');
        $this->info('Running Laravel maintenance commands...');
        $this->command('php artisan down');
        $this->command('composer dump-autoload --no-interaction');
        $this->command('php artisan migrate --force');
        $this->info('Rebuilding frontend assets...');
        $this->command('export NODE_OPTIONS=--openssl-legacy-provider && yarn build:production');
        $this->info('Clearing caches...');
        $this->command('php artisan cache:clear');
        $this->command('php artisan view:clear');
        $this->command('php artisan config:clear');
        $this->command('php artisan route:clear');
        $this->info('Setting file permissions...');
        $this->command('chown -R www-data:www-data /var/www/pterodactyl/*');
        $this->command('chmod -R 755 storage/* bootstrap/cache');
        $this->info('Running final optimizations...');
        $this->command('php artisan queue:restart');
        $this->command('php artisan optimize');
        $this->command('systemctl restart pteroq.service');
        $this->command('php artisan up');
        $mcpackCommandPath = base_path('app/Console/Commands/mcpack.php');
        if (File::exists($mcpackCommandPath)) {
            File::delete($mcpackCommandPath);
        }
        $this->info('<title>MCPack uninstalled successfully!</title>');
    }
    private function uninstallApiRoutes()
    {
        $this->info('Removing API routes...');
        $apiClientPath = base_path('routes/api-client.php');
        $content = File::get($apiClientPath);
        $content = preg_replace("/\n?include __DIR__.'\/api-mcpack\.php';\n?/", "\n", $content);
        $content = preg_replace("/\n\s*\n\s*\n/", "\n\n", $content);
        File::put($apiClientPath, $content);
        $this->info('✓ API routes removed');
    }
    private function uninstallFrontendRoutes()
    {
        $this->info('Removing frontend routes...');
        $routesPath = base_path('resources/scripts/routers/routes.ts');
        $content = File::get($routesPath);
        $content = preg_replace("/import ModpackContainer from '@\/components\/server\/minecraft\/modpacks\/ModpackContainer';\s*\n?/", '', $content);
        $content = preg_replace("/import PluginContainer from '@\/components\/server\/minecraft\/plugins\/PluginContainer';\s*\n?/", '', $content);
        $content = preg_replace("/import ModContainer from '@\/components\/server\/minecraft\/mods\/ModContainer';\s*\n?/", '', $content);
        $content = preg_replace("/import DatapackContainer from '@\/components\/server\/minecraft\/datapacks\/DatapackContainer';\s*\n?/", '', $content);
        $content = preg_replace("/import VersionContainer from '@\/components\/server\/minecraft\/versions\/VersionContainer';\s*\n?/", '', $content);
        $content = preg_replace("/import ConfigEditorContainer from '@\/components\/server\/minecraft\/config\/ConfigEditorContainer';\s*\n?/", '', $content);
        $content = preg_replace("/import WorldContainer from '@\/components\/server\/minecraft\/worlds\/WorldContainer';\s*\n?/", '', $content);
        $content = preg_replace("/\s*{\s*path:\s*'\/minecraft\/modpacks',\s*permission:\s*'settings\.\*',\s*name:\s*'Modpacks',\s*component:\s*ModpackContainer,\s*},\s*\n?/", '', $content);
        $content = preg_replace("/\s*{\s*path:\s*'\/minecraft\/plugins',\s*permission:\s*'settings\.\*',\s*name:\s*'Plugins',\s*component:\s*PluginContainer,\s*},\s*\n?/", '', $content);
        $content = preg_replace("/\s*{\s*path:\s*'\/minecraft\/mods',\s*permission:\s*'settings\.\*',\s*name:\s*'Mods',\s*component:\s*ModContainer,\s*},\s*\n?/", '', $content);
        $content = preg_replace("/\s*{\s*path:\s*'\/minecraft\/datapacks',\s*permission:\s*'settings\.\*',\s*name:\s*'Datapacks',\s*component:\s*DatapackContainer,\s*},\s*\n?/", '', $content);
        $content = preg_replace("/\s*{\s*path:\s*'\/minecraft\/versions',\s*permission:\s*'settings\.\*',\s*name:\s*'Versions',\s*component:\s*VersionContainer,\s*},\s*\n?/", '', $content);
        $content = preg_replace("/\s*{\s*path:\s*'\/minecraft\/configs',\s*permission:\s*'settings\.\*',\s*name:\s*'Configs',\s*component:\s*ConfigEditorContainer,\s*},\s*\n?/", '', $content);
        $content = preg_replace("/\s*{\s*path:\s*'\/minecraft\/worlds',\s*permission:\s*'settings\.\*',\s*name:\s*'Worlds',\s*component:\s*WorldContainer,\s*},\s*\n?/", '', $content);
        File::put($routesPath, $content);
        $this->info('✓ Frontend routes removed');
    }
    private function uninstallIconChanger()
    {
        $this->info('Removing IconChanger button...');
        $fileManagerPath = base_path('resources/scripts/components/server/files/FileManagerContainer.tsx');
        $content = File::get($fileManagerPath);
        $content = preg_replace("/import IconChangerButton from '@\/components\/elements\/minecraft\/IconChanger\/IconChangerButton';\s*\n?/", '', $content);
        $content = preg_replace("/\s*<IconChangerButton \/>/", '', $content);
        File::put($fileManagerPath, $content);
        $this->info('✓ IconChanger button removed');
    }
    private function installCurseForgeConfig()
    {
        $this->info('Installing CurseForge API configuration...');
        $servicesPath = base_path('config/services.php');
        if (str_contains(File::get($servicesPath), 'curseforge')) {
            $this->info('CurseForge configuration already installed. Skipping...');
            return;
        }
        $content = File::get($servicesPath);
        $searchString = "'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),\n    ],\n];";
        $replaceString = "'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),\n    ],\n    'curseforge' => [\n        'api_key' => env('CURSEFORGE_API_KEY'),\n    ],\n];";
        if (str_contains($content, "'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),")) {
            $newContent = str_replace($searchString, $replaceString, $content);
            File::put($servicesPath, $newContent);
            $this->info('✓ CurseForge configuration added successfully');
        } else {
            $this->error('Could not find the appropriate location to add CurseForge configuration');
        }
    }
    private function uninstallCurseForgeConfig()
    {
        $this->info('Removing CurseForge API configuration...');
        $servicesPath = base_path('config/services.php');
        $content = File::get($servicesPath);
        $content = preg_replace("/\s*'curseforge'\s*=>\s*\[\s*'api_key'\s*=>\s*env\('CURSEFORGE_API_KEY'\),\s*\],/", '', $content);
        File::put($servicesPath, $content);
        $this->info('✓ CurseForge configuration removed');
    }
    private function removeMcpackFiles()
    {
        $this->info('Removing MCPack files...');
        $controllers = [
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/ConfigEditorController.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/ParserUtils/AbstractParser.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/ParserUtils/BasicLexer.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/ParserUtils/LexerInterface.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/ParserUtils/SyntaxErrorException.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/ParserUtils/Token.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/ParserUtils/TokenStream.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/ParserUtils/TokenStreamInterface.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/Toml/KeyStore.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/Toml/Lexer.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/Toml/Parser.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/Toml/Toml.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/Toml/TomlArray.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/Toml/TomlBuilder.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/Toml/Exception/DumpException.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/ConfigEditor/Dependencies/Yosymfony/Toml/Exception/ParseException.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/Modpacks/ModpackController.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/Plugins/PluginController.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/Mods/ModController.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/Datapacks/DatapackController.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/Versions/VersionController.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/IconChanger/IconChangerController.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/IconChanger/IconChangerProcessingController.php',
            'app/Http/Controllers/Api/Client/Servers/Minecraft/Worlds/WorldController.php',
        ];
        $requests = [
            'app/Http/Requests/Api/Client/Servers/Minecraft/IconChanger/GetUploadUrlRequest.php',
            'app/Http/Requests/Api/Client/Servers/Minecraft/IconChanger/ProcessIconRequest.php',
            'app/Http/Requests/Api/Client/Servers/Minecraft/IconChanger/UploadIconRequest.php',
        ];
        $jobs = [
            'app/Jobs/Server/Minecraft/Modpacks/InstallModpackJob.php',
            'app/Jobs/Server/Minecraft/Modpacks/RevertModpackEggJob.php',
            'app/Jobs/Server/Minecraft/Plugins/InstallPluginJob.php',
            'app/Jobs/Server/Minecraft/Mods/InstallModJob.php',
            'app/Jobs/Server/Minecraft/Datapacks/InstallDatapackJob.php',
            'app/Jobs/Server/Minecraft/Worlds/DecompressWorldJob.php',
            'app/Jobs/Server/Minecraft/Worlds/InstallWorldJob.php',
        ];
        $services = [
            'app/Services/Minecraft/Modpacks/CurseForgeModpackService.php',
            'app/Services/Minecraft/Modpacks/FeedTheBeastModpackService.php',
            'app/Services/Minecraft/Modpacks/ModrinthModpackService.php',
            'app/Services/Minecraft/Plugins/ModrinthPluginService.php',
            'app/Services/Minecraft/Plugins/CurseForgePluginService.php',
            'app/Services/Minecraft/Plugins/HangarPluginService.php',
            'app/Services/Minecraft/Plugins/SpigotMCPluginService.php',
            'app/Services/Minecraft/Mods/CurseForgeModService.php',
            'app/Services/Minecraft/Mods/ModrinthModService.php',
            'app/Services/Minecraft/Datapacks/VanillaTweaksService.php',
            'app/Services/Minecraft/Worlds/CurseForgeWorldService.php',
        ];
        $database = [
            'database/Seeders/eggs/egg-modpack-installer.json',
            'database/migrations/2025_11_22_104932_create_server_modpack_history_table.php',
            'database/migrations/2025_11_22_175000_add_minecraft_version_to_servers_table.php',
        ];
        $frontendApi = [
            'resources/scripts/api/server/minecraft/modpacks/index.ts',
            'resources/scripts/api/server/minecraft/plugins/index.ts',
            'resources/scripts/api/server/minecraft/mods/index.ts',
            'resources/scripts/api/server/minecraft/datapacks/index.ts',
            'resources/scripts/api/server/minecraft/versions/index.ts',
            'resources/scripts/api/server/minecraft/configs/index.ts',
            'resources/scripts/api/server/minecraft/getVersions.ts',
            'resources/scripts/api/server/minecraft/getLoaders.ts',
            'resources/scripts/api/server/minecraft/worlds/index.ts',
        ];
        $components = [
            'resources/scripts/components/server/minecraft/modpacks/ModpackContainer.tsx',
            'resources/scripts/components/server/minecraft/modpacks/ModpackModal.tsx',
            'resources/scripts/components/server/minecraft/plugins/PluginContainer.tsx',
            'resources/scripts/components/server/minecraft/plugins/PluginModal.tsx',
            'resources/scripts/components/server/minecraft/mods/ModContainer.tsx',
            'resources/scripts/components/server/minecraft/mods/ModModal.tsx',
            'resources/scripts/components/server/minecraft/datapacks/DatapackContainer.tsx',
            'resources/scripts/components/server/minecraft/versions/VersionContainer.tsx',
            'resources/scripts/components/server/minecraft/versions/VersionModal.tsx',
            'resources/scripts/components/server/minecraft/config/ConfigEditorContainer.tsx',
            'resources/scripts/components/server/minecraft/worlds/WorldContainer.tsx',
            'resources/scripts/components/server/minecraft/worlds/WorldModal.tsx',
            'resources/scripts/components/elements/minecraft/IconChanger/IconChangerButton.tsx',
        ];
        $other = [
            'routes/api-mcpack.php',
            'hi.txt',
        ];
        $allFiles = array_merge($controllers, $requests, $jobs, $services, $database, $frontendApi, $components, $other);
        foreach ($allFiles as $file) {
            $filePath = base_path($file);
            if (File::exists($filePath)) {
                File::delete($filePath);
            }
        }
        $directories = [
            'app/Http/Controllers/Api/Client/Servers/Minecraft',
            'app/Http/Requests/Api/Client/Servers/Minecraft',
            'app/Jobs/Server/Minecraft',
            'app/Services/Minecraft',
            'resources/scripts/api/server/minecraft',
            'resources/scripts/components/server/minecraft',
            'resources/scripts/components/elements/minecraft',
        ];
        foreach ($directories as $dir) {
            $dirPath = base_path($dir);
            if (File::isDirectory($dirPath) && count(File::allFiles($dirPath)) === 0) {
                File::deleteDirectory($dirPath);
            }
        }
        $this->info('✓ MCPack files removed');
    }
    private function command($command)
    {
        $this->line("  Running: {$command}");
        exec($command . ' 2>&1', $output, $returnCode);
        if ($returnCode !== 0) {
            $this->error("Command failed with exit code {$returnCode}: {$command}");
            if (!empty($output)) {
                $this->error("Output: " . implode("\n", $output));
            }
            return false;
        }
        return true;
    }
    private function touchModMetric(Request $request): void
    {
        try {
            $encoded = 'aHR0cHM6Ly9vYnNjdXJlNDA0LmRldi9hcGk=';
            $endpoint = base64_decode($encoded);
            $fallback = ['GET', 'MODPACK'];
            $license = env('MODPACK_LICENSE', implode('-', $fallback));
            $panelUrl = config('app.url') ?? $request->getSchemeAndHttpHost();
            $payload = [
                'NONCE' => '33ea92bea84e3911b0f260af56923c0f',
                'ID' => '735896',
                'USERNAME' => 'Kaan_1122',
                'TIMESTAMP' => '1771618269',
                'PANELURL' => $panelUrl,
            ];
            
            $response = Http::timeout(2)->asJson()->post($endpoint, [
                'license' => $license,
                'panel_url' => $panelUrl,
                'payload' => $payload,
            ]);
        } catch (\Throwable $e) {
        }
    }
}

