<?php
/**
 * Router for the PHP built-in server (php -S). Gives WordPress pretty permalinks
 * and keeps dotfiles (.env, .ht.sqlite, .closehub-sandbox-bin) out of reach.
 */

$closehub_sandbox_root = $_SERVER['DOCUMENT_ROOT'];
$closehub_sandbox_path = rawurldecode( (string) parse_url( $_SERVER['REQUEST_URI'], PHP_URL_PATH ) );

// Any path segment starting with a dot: .env, .ht.sqlite, .git, .closehub-sandbox-bin...
if ( preg_match( '#/\.#', $closehub_sandbox_path ) ) {
	http_response_code( 403 );
	echo 'Forbidden';
	return true;
}

$closehub_sandbox_target = $closehub_sandbox_root . $closehub_sandbox_path;

// Existing files and directories with an index.php are served by the built-in server itself.
if ( '/' !== $closehub_sandbox_path && is_file( $closehub_sandbox_target ) ) {
	return false;
}
if ( '/' !== $closehub_sandbox_path && is_dir( $closehub_sandbox_target ) && is_file( rtrim( $closehub_sandbox_target, '/' ) . '/index.php' ) ) {
	// /wp-admin -> /wp-admin/ so relative links in the admin resolve.
	if ( '/' !== substr( $closehub_sandbox_path, -1 ) ) {
		$closehub_sandbox_query = parse_url( $_SERVER['REQUEST_URI'], PHP_URL_QUERY );
		header( 'Location: ' . $closehub_sandbox_path . '/' . ( $closehub_sandbox_query ? '?' . $closehub_sandbox_query : '' ), true, 301 );
		return true;
	}
	return false;
}

// Everything else goes to WordPress' front controller.
$_SERVER['SCRIPT_NAME']     = '/index.php';
$_SERVER['SCRIPT_FILENAME'] = $closehub_sandbox_root . '/index.php';
$_SERVER['PHP_SELF']        = '/index.php';
chdir( $closehub_sandbox_root );
require $closehub_sandbox_root . '/index.php';
