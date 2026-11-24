<?php
/**
 * Run a MySQL dump through $wpdb, so the SQLite drop-in translates every statement.
 * `wp db import` can't be used: it shells out to the mysql client.
 *
 * Usage: wp --path=<site> eval-file import-sql.php <dump.sql> --skip-plugins --skip-themes
 *
 * Expects the format written by closehub-connector-export: one statement ends at a line ending
 * in ';' (values never contain raw newlines, they are escaped as \n).
 *
 * @package closehub-sandbox
 */

global $wpdb;

$closehub_sandbox_file = $args[0] ?? '';
if ( '' === $closehub_sandbox_file || ! is_readable( $closehub_sandbox_file ) ) {
	WP_CLI::error( "Dump not found: {$closehub_sandbox_file}" );
}

$closehub_sandbox_fh     = fopen( $closehub_sandbox_file, 'r' );
$closehub_sandbox_buffer = '';
$closehub_sandbox_ok     = 0;
$closehub_sandbox_errors = array();

$wpdb->suppress_errors( true );
while ( false !== ( $closehub_sandbox_line = fgets( $closehub_sandbox_fh ) ) ) {
	if ( '' === trim( $closehub_sandbox_buffer ) && ( '' === trim( $closehub_sandbox_line ) || str_starts_with( ltrim( $closehub_sandbox_line ), '--' ) ) ) {
		continue;
	}
	$closehub_sandbox_buffer .= $closehub_sandbox_line;
	if ( ! str_ends_with( rtrim( $closehub_sandbox_line, "\r\n" ), ';' ) ) {
		continue;
	}
	$closehub_sandbox_statement = trim( $closehub_sandbox_buffer );
	$closehub_sandbox_buffer    = '';

	// MySQL session settings mean nothing to SQLite.
	if ( preg_match( '/^SET\s+(NAMES|FOREIGN_KEY_CHECKS|SQL_MODE|time_zone)\b/i', $closehub_sandbox_statement ) ) {
		continue;
	}

	if ( false === $wpdb->query( $closehub_sandbox_statement ) ) {
		$closehub_sandbox_errors[] = substr( $closehub_sandbox_statement, 0, 160 ) . ' => ' . $wpdb->last_error;
	} else {
		++$closehub_sandbox_ok;
	}
}
fclose( $closehub_sandbox_fh );

if ( '' !== trim( $closehub_sandbox_buffer ) ) {
	$closehub_sandbox_errors[] = 'Truncated dump: last statement has no terminating semicolon.';
}

foreach ( array_slice( $closehub_sandbox_errors, 0, 10 ) as $closehub_sandbox_error ) {
	WP_CLI::warning( $closehub_sandbox_error );
}
WP_CLI::log( sprintf( 'statements=%d errors=%d', $closehub_sandbox_ok, count( $closehub_sandbox_errors ) ) );
if ( $closehub_sandbox_errors ) {
	WP_CLI::halt( 1 );
}
