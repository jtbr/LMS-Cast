package Plugins::CastBridge::Plugin;

use strict;

use Data::Dumper;
use File::Spec::Functions;
use XML::Simple;
use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Control::Request;

my $prefs = preferences('plugin.castbridge');
my $hasOutputChannels;
my $fade_volume;
my $statusHandler = Slim::Control::Request::addDispatch(['status', '_index', '_quantity'], [1, 1, 1, \&statusQuery]);

$prefs->init({ 
	autorun => 1, 
	opts => '', 
	debugs => '', 
	logging => 0, 
	bin => undef, 
	configfile => "castbridge.xml", 
	profilesURL => initProfilesURL(), 
	autosave => 1, 
	eraselog => 0,
	baseport => '', 
});

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.castbridge',
	'defaultLevel' => 'WARN',
	'description'  => Slim::Utils::Strings::string('PLUGIN_CASTBRIDGE'),
}); 

sub hasOutputChannels {
	my ($self) = @_;
	return $hasOutputChannels->(@_) unless $self->modelName =~ /CastBridge/;
	return 0;
}

sub fade_volume {
	my ($client, $fade, $callback, $callbackargs) = @_;
	# no fade-out, we don't want to have a value of 0 set on pause
	return $fade_volume->($client, $fade, $callback, $callbackargs) if $fade > 0 || $client->modelName !~ /CastBridge/;
	# we should set volume in case some day we use callback directly on fade-in (as Resume/Start may set volume to 0
	return $callback->(@{$callbackargs}) if $callback;
}

sub initPlugin {
	my $class = shift;

	# this is hacky but I won't redefine a whole player model just for this	
	require Slim::Player::SqueezePlay;
	$hasOutputChannels = Slim::Player::SqueezePlay->can('hasOutputChannels');
	*Slim::Player::SqueezePlay::hasOutputChannels = \&hasOutputChannels;
	
	$fade_volume = \&Slim::Player::SqueezePlay::fade_volume;
	*Slim::Player::SqueezePlay::fade_volume = \&fade_volume;
	
	*Slim::Utils::Log::castbridgeLogFile = sub { Plugins::CastBridge::Squeeze2cast->logFile; };

	$class->SUPER::initPlugin(@_);
	
	require Plugins::CastBridge::Squeeze2cast;		
	
	if ($prefs->get('autorun')) {
		Plugins::CastBridge::Squeeze2cast->start;
	}
	
	if (!$::noweb) {
		require Plugins::CastBridge::Settings;
		Plugins::CastBridge::Settings->new;
		# there is a bug in LMS where the "content-type" set in handlers is ignored, only extension matters (and is html by default)
		Slim::Web::Pages->addPageFunction("castbridge-log", \&Plugins::CastBridge::Squeeze2cast::logHandler);
		Slim::Web::Pages->addPageFunction("castbridge-config.xml", \&Plugins::CastBridge::Squeeze2cast::configHandler);
		Slim::Web::Pages->addPageFunction("castbridge-guide", \&Plugins::CastBridge::Squeeze2cast::guideHandler);
	}
	
	$log->warn(Dumper(Slim::Utils::OSDetect::details()));
}

sub initProfilesURL {
	my $file = catdir(Slim::Utils::PluginManager->allPlugins->{'CastBridge'}->{'basedir'}, 'install.xml');
	return XMLin($file, ForceArray => 0, KeepRoot => 0, NoAttr => 0)->{'profilesURL'};
}

sub shutdownPlugin {
	if ($prefs->get('autorun')) {
		Plugins::CastBridge::Squeeze2cast->stop;
	}
}

sub statusQuery {
	my ($request) = @_;
	my $client = $request->client;
	my $song = $request->client->playingSong if $client;
	my $handler = $song->currentTrackHandler if $song;
	
	$statusHandler->($request);
	return unless $client && $song && $handler;

	if ($handler->can('isRepeatingStream') && $handler->isRepeatingStream($song)) {
		my $repeating = 0;

		if ( $handler && $handler->can('getMetadataFor') ) {
			my $url = Slim::Player::Playlist::url($client);
			my $metadata = $handler->getMetadataFor( $client, $url, 'repeating' );
			$repeating = $metadata->{duration} || $metadata->{secs} || 0;
		}
		
		$request->addResult("repeating_stream", $repeating);
	}
}


1;
