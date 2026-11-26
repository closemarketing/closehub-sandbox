<?php
/**
 * Lists the WordPress sites registered in WordPress Studio and LocalWP, one per line, fields
 * separated by \x1f (not a tab: bash `read` would merge empty tab-separated fields):
 *   source  name  wp_root  port  domain  mysql_port
 * port is the port Studio serves the site on (empty for Local); mysql_port is Local's MySQL port
 * while the site runs (empty for Studio). Registries that don't exist are skipped.
 *
 * Usage: php migrate-registry.php STUDIO_CONFIG[,STUDIO_CONFIG...] LOCAL_CONFIG[,LOCAL_CONFIG...]
 * Never prints passwords.
 */

$home = getenv( 'HOME' ) ?: '';

/** Expands a leading ~ to $HOME and drops a trailing slash. */
function closehub_sandbox_path( string $path, string $home ): string {
	if ( '~' === $path || 0 === strpos( $path, '~/' ) ) {
		$path = $home . substr( $path, 1 );
	}
	return rtrim( $path, '/' );
}

/** Separators or newlines in a field would break the line. */
function closehub_sandbox_field( $value ): string {
	return str_replace( array( "\x1f", "\t", "\n", "\r" ), ' ', (string) $value );
}

function closehub_sandbox_row( array $fields ): void {
	echo implode( "\x1f", array_map( 'closehub_sandbox_field', $fields ) ), "\n";
}

foreach ( array_filter( explode( ',', $argv[1] ?? '' ) ) as $file ) {
	if ( ! is_readable( $file ) ) {
		continue;
	}
	$data = json_decode( (string) file_get_contents( $file ), true );
	foreach ( (array) ( $data['sites'] ?? array() ) as $site ) {
		if ( empty( $site['path'] ) ) {
			continue;
		}
		closehub_sandbox_row(
			array(
				'studio',
				$site['name'] ?? basename( $site['path'] ),
				closehub_sandbox_path( $site['path'], $home ),
				$site['port'] ?? '',
				$site['customDomain'] ?? '',
				'',
			)
		);
	}
}

foreach ( array_filter( explode( ',', $argv[2] ?? '' ) ) as $file ) {
	if ( ! is_readable( $file ) ) {
		continue;
	}
	// sites.json is an object keyed by site id.
	$data = json_decode( (string) file_get_contents( $file ), true );
	foreach ( (array) $data as $site ) {
		if ( ! is_array( $site ) || empty( $site['path'] ) ) {
			continue;
		}
		$ports = $site['services']['mysql']['ports']['MYSQL'] ?? array();
		closehub_sandbox_row(
			array(
				'local',
				$site['name'] ?? basename( $site['path'] ),
				closehub_sandbox_path( $site['path'], $home ) . '/app/public',
				'',
				$site['domain'] ?? '',
				is_array( $ports ) ? ( $ports[0] ?? '' ) : $ports,
			)
		);
	}
}
