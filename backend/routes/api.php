<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\ChatRoomController;
use App\Http\Controllers\MessageController;
use App\Http\Controllers\UserController;
use Illuminate\Support\Facades\Route;

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login',    [AuthController::class, 'login']);

Route::middleware('auth:sanctum')->group(function () {

    Route::post('/logout',          [AuthController::class, 'logout']);
    Route::get('/me',               [AuthController::class, 'me']);
    Route::put('/profile',          [AuthController::class, 'updateProfile']);

    Route::prefix('rooms')->group(function () {
        Route::get('/',                      [ChatRoomController::class, 'index']);
        Route::post('/direct',               [ChatRoomController::class, 'createDirect']);
        Route::post('/group',                [ChatRoomController::class, 'createGroup']);
        Route::get('/{chatRoom}',            [ChatRoomController::class, 'show']);
        Route::delete('/{chatRoom}/leave',   [ChatRoomController::class, 'leave']);
        Route::post('/{chatRoom}/members',   [ChatRoomController::class, 'addMembers']);
        Route::get('/{chatRoom}/messages',   [MessageController::class, 'index']);
        Route::post('/{chatRoom}/messages',  [MessageController::class, 'store']);
    });

    Route::put('/messages/{message}',    [MessageController::class, 'update']);
    Route::delete('/messages/{message}', [MessageController::class, 'destroy']);

    Route::get('/users/search', [UserController::class, 'search']);
});
