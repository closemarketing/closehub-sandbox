<?php
/**
 * Plugin Name: closehub-sandbox safety
 * Description: Installed in sandboxes cloned from a live site. Blocks outgoing email and every outgoing HTTP request except WordPress.org, so imported integrations (ERP, CRM, payments, webhooks) can't act on real accounts.
 *
 * Allow extra hosts with CLOSEHUB_SANDBOX_ALLOW_HOSTS in the site .env (comma-separated).
 *
 * @package closehub-sandbox
 */

defined( 'ABSPATH' ) || exit;

// Mail never leaves the sandbox; it is logged to debug.log instead.
add_filter(
	'pre_wp_mail',
	static function ( $short_circuit, $atts ) {
		error_log( '[closehub-sandbox] email blocked: to=' . wp_json_encode( $atts['to'] ?? '' ) . ' subject=' . wp_json_encode( $atts['subject'] ?? '' ) ); // phpcs:ignore WordPress.PHP.DevelopmentFunctions.error_log_error_log
		return true;
	},
	PHP_INT_MAX,
	2
);

// Outgoing HTTP: only WordPress.org (updates, plugin/theme installs) and local hosts.
add_filter(
	'pre_http_request',
	static function ( $preempt, $args, $url ) {
		$host = strtolower( (string) wp_parse_url( $url, PHP_URL_HOST ) );
		if ( '' === $host ) {
			return $preempt;
		}
		$allowed = array( 'localhost', '127.0.0.1', '::1', 'wordpress.org', 'api.wordpress.org', 'downloads.wordpress.org', 's.w.org', 'translate.wordpress.org' );
		$extra   = getenv( 'CLOSEHUB_SANDBOX_ALLOW_HOSTS' );
		if ( false === $extra && isset( $_ENV['CLOSEHUB_SANDBOX_ALLOW_HOSTS'] ) ) {
			$extra = $_ENV['CLOSEHUB_SANDBOX_ALLOW_HOSTS'];
		}
		foreach ( array_filter( array_map( 'trim', explode( ',', (string) $extra ) ) ) as $item ) {
			$allowed[] = strtolower( $item );
		}
		foreach ( $allowed as $item ) {
			if ( $host === $item || str_ends_with( $host, '.' . $item ) ) {
				return $preempt;
			}
		}
		$local = wp_parse_url( home_url(), PHP_URL_HOST );
		if ( $host === $local ) {
			return $preempt;
		}
		error_log( "[closehub-sandbox] HTTP request blocked: {$url}" ); // phpcs:ignore WordPress.PHP.DevelopmentFunctions.error_log_error_log
		return new WP_Error( 'closehub_sandbox_http_blocked', "Outgoing request to {$host} blocked in this sandbox (allow it with CLOSEHUB_SANDBOX_ALLOW_HOSTS)." );
	},
	PHP_INT_MAX,
	3
);
