<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class UserController extends Controller
{
    public function search(Request $request): JsonResponse
    {
        $request->validate(['q' => 'required|string|min:2']);

        $users = User::where('id', '!=', $request->user()->id)
            ->where(function ($query) use ($request) {
                $query->where('name', 'like', "%{$request->q}%")
                      ->orWhere('email', 'like', "%{$request->q}%");
            })
            ->select('id', 'name', 'email', 'avatar', 'last_seen_at')
            ->limit(20)
            ->get()
            ->map(fn($u) => array_merge($u->toArray(), ['is_online' => $u->is_online]));
            
        return response()->json($users);
    }
}
