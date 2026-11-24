<?php
/**
 * Loaded from wp-config.php by sandboxwp-ai. Reads the sandbox .env and defines
 * the WordPress constants it contains. Never used in production.
 */

$sandboxwp_env_file = __DIR__ . '/.env';

if ( is_readable( $sandboxwp_env_file ) ) {
	foreach ( file( $sandboxwp_env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES ) as $sandboxwp_line ) {
		if ( '#' === $sandboxwp_line[0] || false === strpos( $sandboxwp_line, '=' ) ) {
			continue;
		}
		list( $sandboxwp_key, $sandboxwp_value ) = explode( '=', $sandboxwp_line, 2 );
		$_ENV[ $sandboxwp_key ] = $sandboxwp_value;
	}
}

$sandboxwp_constants = array( 'WP_HOME', 'WP_SITEURL', 'WP_ENVIRONMENT_TYPE' );
foreach ( $sandboxwp_constants as $sandboxwp_constant ) {
	if ( ! defined( $sandboxwp_constant ) && ! empty( $_ENV[ $sandboxwp_constant ] ) ) {
		define( $sandboxwp_constant, $_ENV[ $sandboxwp_constant ] );
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

unset( $sandboxwp_env_file, $sandboxwp_line, $sandboxwp_key, $sandboxwp_value, $sandboxwp_constants, $sandboxwp_constant );
