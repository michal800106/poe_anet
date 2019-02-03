#!/usr/bin/perl
use warnings;
use strict;
use POE;
use POE::Wheel::ReadWrite;
use POE::Wheel::ReadLine;
use Symbol qw(gensym);
use Device::SerialPort;
use POE::Filter::Line;
POE::Session->create(
  inline_states => {
    _start      => \&setup_device,
    got_port    => \&display_port_data,
    got_console => \&transmit_console_data,
    got_error   => \&handle_errors,
  },
);
POE::Kernel->run();
exit 0;

sub setup_device {
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  # Open a serial port, and tie it to a file handle for POE.
  my $handle = gensym();
  my $port = tie(*$handle, "Device::SerialPort", "/dev/ttyUSB0");
  die "can't open port: $!" unless $port;
  $port->datatype('raw');
  $port->baudrate(115200);
  $port->databits(8);
  $port->parity("none");
  $port->stopbits(1);
  #$port->handshake("rts");
  $port->write_settings();

  # Start interacting with the GPS.
  $heap->{port}       = $port;
  $heap->{port_wheel} = POE::Wheel::ReadWrite->new(
    Handle => $handle,
    Filter => POE::Filter::Line->new(
      InputLiteral  => undef, # "\x0D\x0A",    # Received line endings.
      OutputLiteral => "\x0D",        # Sent line endings.
    ),
    InputEvent => "got_port",
    ErrorEvent => "got_error",
  );

  # Start a wheel to interact with the console, and prompt the user.
  $heap->{console} = POE::Wheel::ReadLine->new(InputEvent => "got_console",);
  $heap->{console}->put("Press ^D to stop.");
  $heap->{console}->get("Ready: ");
}

# Port data (lines, separated by CRLF) are displayed on the console.
sub display_port_data {
  my ($heap, $data) = @_[HEAP, ARG0];
  $heap->{console}->put($data);
}

# Console input is sent to the device.
sub transmit_console_data {
  my ($heap, $input) = @_[HEAP, ARG0];
  if (defined $input) {
    $heap->{console}->addhistory($input);
    $heap->{port_wheel}->put($input);
    $heap->{console}->get("Ready: ");

    # Clearing $! after $serial_port_wheel->put() seems to work around
    # an issue in Device::SerialPort 1.000_002.
    $! = 0;
    return;
  }
  $heap->{console}->put("Bye!");
  delete $heap->{port_wheel};
  delete $heap->{console};
}

# Error on the serial port.  Shut down.
sub handle_errors {
  my $heap = $_[HEAP];
  $heap->{console}->put("$_[ARG0] error $_[ARG1]: $_[ARG2]");
  $heap->{console}->put("bye!");
  delete $heap->{console};
  delete $heap->{port_wheel};
}
