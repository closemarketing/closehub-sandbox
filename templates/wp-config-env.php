<?php
/**
 * Loaded from wp-config.php by closehub-sandbox. Reads the sandbox .env and defines
 * the WordPress constants it contains. Never used in production.
 */

$closehub_sandbox_env_file = __DIR__ . '/.env';

if ( is_readable( $closehub_sandbox_env_file ) ) {
	foreach ( file( $closehub_sandbox_env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES ) as $closehub_sandbox_line ) {
		if ( '#' === $closehub_sandbox_line[0] || false === strpos( $closehub_sandbox_line, '=' ) ) {
			continue;
		}
		list( $closehub_sandbox_key, $closehub_sandbox_value ) = explode( '=', $closehub_sandbox_line, 2 );
		$_ENV[ $closehub_sandbox_key ] = $closehub_sandbox_value;
	}
}

$closehub_sandbox_constants = array( 'WP_HOME', 'WP_SITEURL', 'WP_ENVIRONMENT_TYPE' );
foreach ( $closehub_sandbox_constants as $closehub_sandbox_constant ) {
	if ( ! defined( $closehub_sandbox_constant ) && ! empty( $_ENV[ $closehub_sandbox_constant ] ) ) {
		define( $closehub_sandbox_constant, $_ENV[ $closehub_sandbox_constant ] );
	}
}

// Debug on, but logged to wp-content/debug.log instead of breaking JSON/REST responses.
if ( ! defined( 'WP_DEBUG' ) ) {
	define( 'WP_DEBUG', 'true' === ( $_ENV['WP_DEBUG'] ?? 'false' ) );
}
if ( ! defined( 'WP_DEBUG_LOG' ) ) {
	define( 'WP_DEBUG_LOG', WP_DEBUG );
}
if ( ! defined( 'WP_DEBUG_DISPLAY' ) ) {
	define( 'WP_DEBUG_DISPLAY', false );
}

unset( $closehub_sandbox_env_file, $closehub_sandbox_line, $closehub_sandbox_key, $closehub_sandbox_value, $closehub_sandbox_constants, $closehub_sandbox_constant );
