<?php
/**
 * Dump the WordPress tables of a MySQL database (LocalWP) in the format import-sql.php reads:
 * DROP + CREATE + INSERT, one statement ending at a line ending in ';', values escaped like
 * closehub-connector-export (no raw newlines; non-UTF-8 values as 0x hex).
 * Plain PHP + mysqli: doesn't need the mysql client or mysqldump.
 *
 * Usage: php mysql-dump.php --database DB --user USER --prefix PREFIX --out FILE
 *          [--host 127.0.0.1] [--port N] [--socket PATH]
 * The password comes from the CLOSEHUB_SANDBOX_DB_PASSWORD environment variable.
 *
 * @package closehub-sandbox
 */

$opts = getopt( '', array( 'database:', 'user:', 'prefix:', 'out:', 'host:', 'port:', 'socket:' ) );
foreach ( array( 'database', 'user', 'prefix', 'out' ) as $required ) {
	if ( empty( $opts[ $required ] ) ) {
		fwrite( STDERR, "mysql-dump: --{$required} is required\n" );
		exit( 2 );
	}
}
if ( ! extension_loaded( 'mysqli' ) ) {
	fwrite( STDERR, "mysql-dump: the PHP mysqli extension is required\n" );
	exit( 2 );
}

mysqli_report( MYSQLI_REPORT_OFF );
$db = @new mysqli(
	$opts['host'] ?? '127.0.0.1',
	$opts['user'],
	(string) getenv( 'CLOSEHUB_SANDBOX_DB_PASSWORD' ),
	$opts['database'],
	(int) ( $opts['port'] ?? 3306 ),
	$opts['socket'] ?? null
);
if ( $db->connect_errno ) {
	fwrite( STDERR, "mysql-dump: cannot connect to MySQL: {$db->connect_error}\n" );
	exit( 3 );
}
$db->set_charset( 'utf8mb4' );

/** Same escaping as CloseHub_Export_DB::sql_value(). */
function closehub_sandbox_sql_value( $value ): string {
	if ( null === $value ) {
		return 'NULL';
	}
	$value = (string) $value;
	if ( '' !== $value && ! preg_match( '//u', $value ) ) {
		return '0x' . bin2hex( $value );
	}
	return "'" . strtr(
		$value,
		array(
			'\\'   => '\\\\',
			"\0"   => '\\0',
			"\n"   => '\\n',
			"\r"   => '\\r',
			"'"    => "\\'",
			'"'    => '\\"',
			"\x1a" => '\\Z',
		)
	) . "'";
}

$out = fopen( $opts['out'], 'w' );
if ( ! $out ) {
	fwrite( STDERR, "mysql-dump: cannot write {$opts['out']}\n" );
	exit( 2 );
}

// Only this site's tables: a Local database may be shared or hold leftovers.
$like   = $db->real_escape_string( strtr( $opts['prefix'], array( '_' => '\\_', '%' => '\\%' ) ) ) . '%';
$tables = array();
$result = $db->query( "SHOW TABLES LIKE '{$like}'" );
while ( $result && ( $row = $result->fetch_row() ) ) {
	$tables[] = $row[0];
}
if ( ! $tables ) {
	fwrite( STDERR, "mysql-dump: no tables with prefix {$opts['prefix']} in {$opts['database']}\n" );
	exit( 4 );
}

$rows_total = 0;
foreach ( $tables as $table ) {
	$create = $db->query( "SHOW CREATE TABLE `{$table}`" )->fetch_row()[1];
	fwrite( $out, "DROP TABLE IF EXISTS `{$table}`;\n{$create};\n" );

	// Unbuffered: big tables don't have to fit in memory.
	$result = $db->query( "SELECT * FROM `{$table}`", MYSQLI_USE_RESULT );
	$batch  = array();
	$cols   = null;
	while ( $result && ( $row = $result->fetch_assoc() ) ) {
		$cols    = $cols ?? '`' . implode( '`, `', array_keys( $row ) ) . '`';
		$batch[] = '(' . implode( ', ', array_map( 'closehub_sandbox_sql_value', $row ) ) . ')';
		if ( count( $batch ) >= 500 ) {
			fwrite( $out, "INSERT INTO `{$table}` ({$cols}) VALUES\n" . implode( ",\n", $batch ) . ";\n" );
			$rows_total += count( $batch );
			$batch       = array();
		}
	}
	if ( $batch ) {
		fwrite( $out, "INSERT INTO `{$table}` ({$cols}) VALUES\n" . implode( ",\n", $batch ) . ";\n" );
		$rows_total += count( $batch );
	}
	if ( $result ) {
		$result->free();
	}
}
fclose( $out );
fwrite( STDERR, sprintf( "mysql-dump: tables=%d rows=%d\n", count( $tables ), $rows_total ) );
