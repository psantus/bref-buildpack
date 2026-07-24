<?php

declare(strict_types=1);

return function (array $event): array {
    return [
        'statusCode' => 200,
        'body' => json_encode(['message' => 'Hello from Bref buildpack!']),
    ];
};
