<?php
namespace OPNsense\Mihomo;

require_once __DIR__ . '/Logs.php';

/** Stable configd/API result envelope. Human-readable output never decides success. */
class ActionResult
{
    public static function make(string $state, bool $changed = false, string $code = '', string $message = '', array $extra = []): array
    {
        if (!in_array($state, ['completed', 'unchanged', 'accepted', 'failed', 'partial'], true)) {
            throw new \InvalidArgumentException('Unknown action state');
        }
        return array_merge($extra, [
            'status' => in_array($state, ['failed', 'partial'], true) ? $state : 'ok',
            'state' => $state, 'changed' => $changed, 'code' => $code ?: $state,
            'message' => $message,
        ]);
    }

    public static function parse(string $raw): array
    {
        $data = json_decode(trim($raw), true);
        if (!is_array($data) || !isset($data['state'], $data['status'], $data['changed'], $data['code'])
            || !in_array($data['state'], ['completed', 'unchanged', 'accepted', 'failed', 'partial'], true)
            || !is_bool($data['changed']) || !is_string($data['code']) || !is_string($data['message'] ?? null)
            || $data['status'] !== (in_array($data['state'], ['failed', 'partial'], true) ? $data['state'] : 'ok')) {
            return self::make('failed', false, 'invalid_result', 'The backend did not return a valid action result.');
        }
        $data['message'] = Logs::redact($data['message']);
        if (isset($data['messages'])) {
            if (!is_array($data['messages']) || count(array_filter($data['messages'], 'is_string')) !== count($data['messages'])) {
                return self::make('failed', false, 'invalid_result', 'The backend returned invalid action messages.');
            }
            $data['messages'] = array_map([Logs::class, 'redact'], $data['messages']);
        }
        return $data;
    }

    public static function emit(array $result): void
    {
        echo json_encode($result, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
    }
}
