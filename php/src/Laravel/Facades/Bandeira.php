<?php

declare(strict_types=1);

namespace Bandeira\Laravel\Facades;

use Bandeira\Laravel\LaravelClient;
use Illuminate\Support\Facades\Facade;

final class Bandeira extends Facade
{
    protected static function getFacadeAccessor(): string
    {
        return LaravelClient::class;
    }
}
