<?php

namespace App\Http\Controllers;

use App\Models\ChatRoom;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ChatRoomController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $rooms = $request->user()
            ->chatRooms()
            ->with(['latestMessage.user', 'members'])
            ->get()
            ->map(function ($room) use ($request) {
                $room->unread_count = $room->getUnreadCountForUser($request->user()->id);
                return $room;
            })
            ->sortByDesc(fn($r) => optional($r->latestMessage)->created_at)
            ->values();

        return response()->json($rooms);
    }

    public function createDirect(Request $request): JsonResponse
    {
        $request->validate(['user_id' => 'required|exists:users,id']);

        $targetUser = User::findOrFail($request->user_id);
        $me         = $request->user();

        $existingRoom = ChatRoom::where('type', 'direct')
            ->whereHas('members', fn($q) => $q->where('user_id', $me->id))
            ->whereHas('members', fn($q) => $q->where('user_id', $targetUser->id))
            ->first();

        if ($existingRoom) {
            return response()->json($existingRoom->load('members'));
        }

        $room = ChatRoom::create([
            'name'       => "{$me->name} & {$targetUser->name}",
            'type'       => 'direct',
            'created_by' => $me->id,
        ]);

        $room->members()->attach([
            $me->id         => ['role' => 'admin'],
            $targetUser->id => ['role' => 'member'],
        ]);
        
        return response()->json($room->load('members'), 201);
    }

    public function createGroup(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name'         => 'required|string|max:100',
            'description'  => 'nullable|string|max:500',
            'member_ids'   => 'nullable|array',
            'member_ids.*' => 'exists:users,id',
        ]);

        $me   = $request->user();
        $room = ChatRoom::create([
            'name'        => $validated['name'],
            'description' => $validated['description'] ?? null,
            'type'        => 'group',
            'created_by'  => $me->id,
        ]);

        $members = [$me->id => ['role' => 'admin']];
        foreach ($validated['member_ids'] ?? [] as $userId) {
            if ($userId != $me->id) {
                $members[$userId] = ['role' => 'member'];
            }
        }
        $room->members()->attach($members);

        return response()->json($room->load('members'), 201);
    }

    public function show(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        abort_unless($chatRoom->members()->where('user_id', $request->user()->id)->exists(), 403);
        return response()->json($chatRoom->load('members'));
    }

    public function addMembers(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        abort_unless($chatRoom->members()->where('user_id', $request->user()->id)->exists(), 403);

        $request->validate([
            'user_ids'   => 'required|array',
            'user_ids.*' => 'exists:users,id',
        ]);

        $newMembers = [];
        foreach ($request->user_ids as $userId) {
            if (!$chatRoom->members()->where('user_id', $userId)->exists()) {
                $newMembers[$userId] = ['role' => 'member'];
            }
        }

        if (!empty($newMembers)) {
            $chatRoom->members()->attach($newMembers);
        }

        return response()->json($chatRoom->load('members'));
    }

    public function leave(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        abort_unless($chatRoom->type === 'group', 422, '個別チャットは退出できません。');
        $chatRoom->members()->detach($request->user()->id);
        return response()->json(['message' => 'グループを退出しました。']);
    }

    public function destroy(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        abort_unless($chatRoom->type === 'group', 422, 'グループのみ解散できます。');
        abort_unless(
            $chatRoom->members()
                ->where('user_id', $request->user()->id)
                ->wherePivot('role', 'admin')
                ->exists(),
            403,
            '管理者のみグループを解散できます。'
        );

        $this->broadcast($chatRoom, 'room.dissolved', ['chat_room_id' => $chatRoom->id]);
        $chatRoom->delete();

        return response()->json(['message' => 'グループを解散しました。']);
    }

    public function update(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        abort_unless($chatRoom->type === 'group', 422, 'グループのみ名前を変更できます。');
        abort_unless($chatRoom->members()->where('user_id', $request->user()->id)->exists(), 403);

        $validated = $request->validate(['name' => 'required|string|max:100']);
        $chatRoom->update(['name' => $validated['name']]);

        $this->broadcast($chatRoom, 'room.updated', ['name' => $chatRoom->name, 'avatar' => $chatRoom->avatar]);

        return response()->json($chatRoom);
    }

    public function updateAvatar(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        abort_unless($chatRoom->members()->where('user_id', $request->user()->id)->exists(), 403);

        $request->validate(['avatar' => 'required|image|max:5120']);

        $path = $request->file('avatar')->store('room-avatars', 'public');
        $chatRoom->update(['avatar' => url('api/storage/' . $path)]);

        $this->broadcast($chatRoom, 'room.updated', ['name' => $chatRoom->name, 'avatar' => $chatRoom->avatar]);

        return response()->json($chatRoom);
    }

    private function broadcast(ChatRoom $chatRoom, string $event, array $data): void
    {
        if (!env('PUSHER_APP_KEY') || !env('PUSHER_APP_SECRET') || !env('PUSHER_APP_ID')) {
            return;
        }

        $pusher = new \Pusher\Pusher(
            env('PUSHER_APP_KEY'),
            env('PUSHER_APP_SECRET'),
            env('PUSHER_APP_ID'),
            ['cluster' => env('PUSHER_APP_CLUSTER'), 'useTLS' => true]
        );

        $pusher->trigger("chat-room.{$chatRoom->id}", $event, $data);
    }
}
