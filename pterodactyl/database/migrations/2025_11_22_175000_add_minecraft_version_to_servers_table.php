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
        Schema::table('servers', function (Blueprint $table) {
            if (!Schema::hasColumn('servers', 'minecraft_type')) {
                $table->string('minecraft_type')->nullable()->after('description');
            }
            if (!Schema::hasColumn('servers', 'minecraft_version')) {
                $table->string('minecraft_version')->nullable()->after('minecraft_type');
            }
            if (!Schema::hasColumn('servers', 'minecraft_build')) {
                $table->string('minecraft_build')->nullable()->after('minecraft_version');
            }
        });
    }
    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('servers', function (Blueprint $table) {
            $table->dropColumn(['minecraft_type', 'minecraft_version', 'minecraft_build']);
        });
    }
};
