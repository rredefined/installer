<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('server_modpack_history', function (Blueprint $table) {
            $table->id();
            $table->unsignedInteger('server_id');
            $table->string('provider');
            $table->string('modpack_id');
            $table->string('name');
            $table->string('version_id')->nullable();
            $table->string('icon_url')->nullable();
            $table->timestamps();

            $table->foreign('server_id')->references('id')->on('servers')->onDelete('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('server_modpack_history');
    }
};
