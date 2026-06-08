<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Message extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = [
        'chat_room_id', 'user_id', 'content', 'type',
        'file_url', 'reply_to_id', 'is_edited',
    ];

    protected $casts = [
        'is_edited' => 'boolean',
        'read_at'   => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function chatRoom()
    {
        return $this->belongsTo(ChatRoom::class);
    }

    public function replyTo()
    {
        return $this->belongsTo(Message::class, 'reply_to_id');
    }
}
