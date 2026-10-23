<?php

namespace OPNsense\Mihomo;

/** Plugin catalog follows the locale chosen by WebGUI; core translations remain intact. */
class Translator
{
    public function __construct()
    {
        bindtextdomain('os-mihomo', __DIR__ . '/Locale');
        bind_textdomain_codeset('os-mihomo', 'UTF-8');
    }

    public function _($message, $placeholders = []): string
    {
        $text = dgettext('os-mihomo', (string)$message);
        if ($text === (string)$message) {
            $text = gettext((string)$message);
        }
        foreach ((array)$placeholders as $key => $value) {
            $text = str_replace('%' . $key . '%', (string)$value, $text);
        }
        return $text;
    }

    /** Translate plugin forms without modifying the shared system catalog. */
    public function form(array $fields): array
    {
        foreach ($fields as $key => $value) {
            if (is_array($value)) {
                $fields[$key] = $this->form($value);
            } elseif (is_string($value) && in_array($key, ['label', 'help', 'hint'], true)) {
                $fields[$key] = $this->_($value);
            }
        }
        return $fields;
    }
}
