<?php

declare(strict_types=1);

namespace Bandeira\Laravel\Contracts;

use Bandeira\Context;

interface ContextResolver
{
    public function resolve(): Context;
}
