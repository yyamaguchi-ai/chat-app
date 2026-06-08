<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chat_rooms', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->text('description')->nullable();
            $table->enum('type', ['direct', 'group'])->default('direct');
            $table->foreignId('created_by')->constrained('users')->onDelete('cascade');
            $table->string('avatar')->nullable();
            $table->timestamps();
        });

        Schema::create('chat_room_members', function (Blueprint $table) {
            $table->id();
            $table->foreignId('chat_room_id')->constrained()->onDelete('cascade');
            $table->foreignId('user_id')->constrained()->onDelete('cascade');
            $table->enum('role', ['admin', 'member'])->default('member');
            $table->timestamp('joined_at')->useCurrent();
            $table->timestamp('last_read_at')->nullable();
            $table->unique(['chat_room_id', 'user_id']);
            $table->timestamps();
        });

        Schema::create('messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('chat_room_id')->constrained()->onDelete('cascade');
            $table->foreignId('user_id')->constrained()->onDelete('cascade');
            $table->text('content');
            $table->enum('type', ['text', 'image', 'file'])->default('text');
            $table->string('file_url')->nullable();
            $table->foreignId('reply_to_id')->nullable()->constrained('messages')->onDelete('set null');
            $table->boolean('is_edited')->default(false);
            $table->timestamp('read_at')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('messages');
        Schema::dropIfExists('chat_room_members');
        Schema::dropIfExists('chat_rooms');
    }
};
