<?php

namespace App\Http\Controllers;

use App\Models\ChatRoom;
use App\Models\Message;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MessageController extends Controller
{
    public function index(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        abort_unless($chatRoom->members()->where('user_id', $request->user()->id)->exists(), 403);

        $messages = $chatRoom->messages()
            ->with(['user', 'replyTo.user'])
            ->orderBy('created_at', 'desc')
            ->paginate(50);

        $chatRoom->members()
            ->where('user_id', $request->user()->id)
            ->update(['last_read_at' => now()]);

        return response()->json($messages);
    }

    public function store(Request $request, ChatRoom $chatRoom): JsonResponse
    {
        abort_unless($chatRoom->members()->where('user_id', $request->user()->id)->exists(), 403);

        $validated = $request->validate([
            'content'     => 'required|string|max:5000',
            'type'        => 'nullable|in:text,image,file',
            'reply_to_id' => 'nullable|exists:messages,id',
        ]);

        $message = Message::create([
            'chat_room_id' => $chatRoom->id,
            'user_id'      => $request->user()->id,
            'content'      => $validated['content'],
            'type'         => $validated['type'] ?? 'text',
            'reply_to_id'  => $validated['reply_to_id'] ?? null,
        ]);

        $message->load(['user', 'replyTo.user']);

        return response()->json($message, 201);
    }

    public function update(Request $request, Message $message): JsonResponse
    {
        abort_unless($message->user_id === $request->user()->id, 403);
        $request->validate(['content' => 'required|string|max:5000']);

        $message->update([
            'content'   => $request->content,
            'is_edited' => true,
        ]);

        return response()->json($message->load('user'));
    }

    public function destroy(Request $request, Message $message): JsonResponse
    {
        abort_unless($message->user_id === $request->user()->id, 403);
        $message->delete();
        return response()->json(['message' => '削除しました。']);
    }
}
