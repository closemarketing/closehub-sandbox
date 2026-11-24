<?php
/**
 * Router for the PHP built-in server (php -S). Gives WordPress pretty permalinks
 * and keeps dotfiles (.env, .ht.sqlite, .sandboxwp-bin) out of reach.
 */

$sandboxwp_root = $_SERVER['DOCUMENT_ROOT'];
$sandboxwp_path = rawurldecode( (string) parse_url( $_SERVER['REQUEST_URI'], PHP_URL_PATH ) );

// Any path segment starting with a dot: .env, .ht.sqlite, .git, .sandboxwp-bin...
if ( preg_match( '#/\.#', $sandboxwp_path ) ) {
	http_response_code( 403 );
	echo 'Forbidden';
	return true;
}

$sandboxwp_target = $sandboxwp_root . $sandboxwp_path;

// Existing files and directories with an index.php are served by the built-in server itself.
if ( '/' !== $sandboxwp_path && is_file( $sandboxwp_target ) ) {
	return false;
}
if ( '/' !== $sandboxwp_path && is_dir( $sandboxwp_target ) && is_file( rtrim( $sandboxwp_target, '/' ) . '/index.php' ) ) {
	// /wp-admin -> /wp-admin/ so relative links in the admin resolve.
	if ( '/' !== substr( $sandboxwp_path, -1 ) ) {
		$sandboxwp_query = parse_url( $_SERVER['REQUEST_URI'], PHP_URL_QUERY );
		header( 'Location: ' . $sandboxwp_path . '/' . ( $sandboxwp_query ? '?' . $sandboxwp_query : '' ), true, 301 );
		return true;
	}
	return false;
}

// Everything else goes to WordPress' front controller.
$_SERVER['SCRIPT_NAME']     = '/index.php';
$_SERVER['SCRIPT_FILENAME'] = $sandboxwp_root . '/index.php';
$_SERVER['PHP_SELF']        = '/index.php';
chdir( $sandboxwp_root );
require $sandboxwp_root . '/index.php';
