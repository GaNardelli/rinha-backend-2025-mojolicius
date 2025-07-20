package Controller::PaymentProcessor;

sub new {
    my ($class, $args) = @_;
    my $self = {
        test => "test"
    };
    bless $self, $class;
    return $self;
}

1;