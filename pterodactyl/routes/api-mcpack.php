<?php

use Illuminate\Support\Facades\Route;
use Pterodactyl\Http\Controllers\Api\Client;

Route::group(['prefix' => '/modpacks'], function () {
    Route::get('/', [Client\Servers\Minecraft\Modpacks\ModpackController::class, 'index']);
    Route::get('/recent', [Client\Servers\Minecraft\Modpacks\ModpackController::class, 'recent']);
    Route::get('/{modpack}/versions', [Client\Servers\Minecraft\Modpacks\ModpackController::class, 'versions']);
    Route::post('/install', [Client\Servers\Minecraft\Modpacks\ModpackController::class, 'store']);
});

Route::group(['prefix' => '/plugins'], function () {
    Route::get('/', [Client\Servers\Minecraft\Plugins\PluginController::class, 'index']);
    Route::get('/{plugin}/versions', [Client\Servers\Minecraft\Plugins\PluginController::class, 'versions']);
    Route::post('/install', [Client\Servers\Minecraft\Plugins\PluginController::class, 'store']);
});

Route::group(['prefix' => '/mods'], function () {
    Route::get('/', [Client\Servers\Minecraft\Mods\ModController::class, 'index']);
    Route::get('/{mod}/versions', [Client\Servers\Minecraft\Mods\ModController::class, 'versions']);
    Route::post('/install', [Client\Servers\Minecraft\Mods\ModController::class, 'store']);
});

Route::group(['prefix' => '/datapacks'], function () {
    Route::get('/', [Client\Servers\Minecraft\Datapacks\DatapackController::class, 'index']);
    Route::get('/versions', [Client\Servers\Minecraft\Datapacks\DatapackController::class, 'getVersions']);
    Route::get('/image', [Client\Servers\Minecraft\Datapacks\DatapackController::class, 'image']);
    Route::post('/install', [Client\Servers\Minecraft\Datapacks\DatapackController::class, 'install']);
    Route::get('/detect-version', [Client\Servers\Minecraft\Datapacks\DatapackController::class, 'detectVersion']);
    Route::get('/worlds', [Client\Servers\Minecraft\Datapacks\DatapackController::class, 'worlds']);
});

Route::group(['prefix' => '/versions'], function () {
    Route::get('/forks', [Client\Servers\Minecraft\Versions\VersionController::class, 'getMinecraftForks']);
    Route::get('/versions/{type}', [Client\Servers\Minecraft\Versions\VersionController::class, 'getVersions']);
    Route::get('/builds/{type}/{version}', [Client\Servers\Minecraft\Versions\VersionController::class, 'getBuilds']);
    Route::post('/install', [Client\Servers\Minecraft\Versions\VersionController::class, 'updateMinecraftVersion']);
    Route::get('/current', [Client\Servers\Minecraft\Versions\VersionController::class, 'getCurrentVersion']);
});

Route::group(['prefix' => '/configs'], function () {
    Route::get('/', [Client\Servers\Minecraft\ConfigEditor\ConfigEditorController::class, 'index']);
    Route::post('/save', [Client\Servers\Minecraft\ConfigEditor\ConfigEditorController::class, 'save']);
});

Route::group(['prefix' => '/worlds'], function () {
    Route::get('/', [Client\Servers\Minecraft\Worlds\WorldController::class, 'index']);
    Route::get('/installed', [Client\Servers\Minecraft\Worlds\WorldController::class, 'installed']);
    Route::post('/delete', [Client\Servers\Minecraft\Worlds\WorldController::class, 'deleteWorld']);
    Route::post('/set-active', [Client\Servers\Minecraft\Worlds\WorldController::class, 'setActiveWorld']);
    Route::get('/{world}/versions', [Client\Servers\Minecraft\Worlds\WorldController::class, 'versions']);
    Route::post('/install', [Client\Servers\Minecraft\Worlds\WorldController::class, 'store']);
    Route::get('/download-status/{downloadId}', [Client\Servers\Minecraft\Worlds\WorldController::class, 'downloadStatus']);
    Route::post('/query', [Client\Servers\Minecraft\Worlds\WorldController::class, 'queryFile']);
});
