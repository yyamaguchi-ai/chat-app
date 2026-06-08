<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ChatRoom extends Model
{
    use HasFactory;

    protected $fillable = [
        'name', 'description', 'type', 'created_by', 'avatar',
    ];

    public function members()
    {
        return $this->belongsToMany(User::class, 'chat_room_members')
            ->withPivot('role', 'last_read_at')
            ->withTimestamps();
    }

    public function messages()
    {
        return $this->hasMany(Message::class)->orderBy('created_at');
    }

    public function latestMessage()
    {
        return $this->hasOne(Message::class)->latestOfMany();
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function getUnreadCountForUser(int $userId): int
    {
        $member = $this->members()->where('user_id', $userId)->first();
        if (!$member) return 0;

        $lastRead = $member->pivot->last_read_at;
        return $this->messages()
            ->where('user_id', '!=', $userId)
            ->when($lastRead, fn($q) => $q->where('created_at', '>', $lastRead))
            ->count();
    }
}
