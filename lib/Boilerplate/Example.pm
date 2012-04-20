package Boilerplate::Example;
use Mojo::Base 'Mojolicious::Controller';
use Math::Financial;
use Data::Dumper;
use utf8;

# This action will render a template
sub welcome {
  my $self = shift;

  push @{ $self->session->{error_messages} },  'You have to login to proceed!!' if !defined $self->session->{user};  

  # Render template "example/welcome.html.ep" with message
  $self->render(
    message => 'Use this project as a way to quick start any new project!!');
}


sub get_assets_value {
  my ($month) = shift;
  my $start_config = shift;
  $month->{assets_value} = $month->{num_aps} * $start_config->{apartment_value} + $month->{cash} - $month->{debt};
  $month->{total_possible_credit} = ( 1 + $start_config->{percent_from_assured} / 100 ) * $month->{assets_value};

  my $calc = new Math::Financial(
    ir => $start_config->{credit_interest_rate},
    pmt => $month->{total_to_invest},
    np => $start_config->{max_months_per_credit},

  );

  $month->{max_credit_on_time} = $calc->loan_size();

  return $month;
} ## --- end sub get_assets_value

sub buy_aps {

  my ($month) = shift;
  my $start_config = shift; 
  $month->{assets_value} = $month->{num_aps} * $start_config->{apartment_value} + $month->{cash} - $month->{debt};
  $month->{total_possible_credit} = ( 1 + $start_config->{percent_from_assured} / 100 ) * $month->{assets_value};

  my $calc = new Math::Financial(
    ir => $start_config->{credit_interest_rate},
    pmt => $month->{total_to_invest},
    np => $start_config->{max_months_per_credit},
  );

  $month->{max_credit_on_time} = $calc->loan_size();

  if ( $month->{max_credit_on_time} + $month->{cash} >= $start_config->{apartment_value}
    && $month->{total_possible_credit} + $month->{cash} >= $month->{max_credit_on_time} )
  {

    my $aps_to_buy = int( ( $month->{max_credit_on_time} + $month->{cash} ) / $start_config->{apartment_value} );

    $month->{credit} = $start_config->{apartment_value} * $aps_to_buy - $month->{cash};

    my $calc_period = new Math::Financial(
      ir => $start_config->{credit_interest_rate},
      pmt => $month->{total_to_invest},
      pv => $month->{credit},
    );

    $month->{debt} = int( $calc_period->loan_term() * $month->{total_to_invest} + 0.5 );
    $month->{cash} = 0;

    $month->{num_aps} += $aps_to_buy;
  }

  return $month;
} ## --- end sub buy_aps

sub next_month_stats {
  my ($month_object) = shift;
  my $start_config = shift;  

  my $monthly_taxes = $start_config->{annual_taxes} / 12;
  my $monthly_reparations = $start_config->{annual_reparations} / 12;

  if ( $month_object->{debt} > 0 ) {
    $month_object->{debt} -= $month_object->{total_to_invest};

    if ( $month_object->{debt} < 0 ) {
      $month_object->{cash} += -1 * $month_object->{debt};
      $month_object->{debt} = 0;
    }
    #new added
    $month_object->{credit_value} = $start_config->{apartment_value} - $month_object->{cash};
    #
    return $month_object;
  }

  $month_object->{cash} += $month_object->{total_to_invest};

  if ( $month_object->{cash} >= $start_config->{down_payment} ) {

    $month_object->{num_aps} += 1;

    # $month_object = buy_aps( $month_object );
    $month_object->{total_to_invest} =
      $start_config->{monthly_investment}
      + ( $month_object->{num_aps} * ( $start_config->{monthly_rent} - $monthly_taxes - $monthly_reparations ) );

    while ( $month_object->{cash} > $start_config->{apartment_value} ) {
      $month_object->{cash} -= $start_config->{apartment_value};
      $month_object->{num_aps} += 1;
    }

    $month_object->{credit_value} = $start_config->{apartment_value} - $month_object->{cash};
    #warn $month_object->{credit_value};
    my $calc = new Math::Financial(
      pv => $month_object->{credit_value},
      ir => $start_config->{credit_interest_rate},
      pmt => $month_object->{total_to_invest},
    );

    #say $calc->loan_term();
    #print Dumper( $month_object->{total_to_invest} );
    $month_object->{debt} = int( $calc->loan_term() * $month_object->{total_to_invest} + 0.5 );
    $month_object->{cash} = 0;
  }

  return $month_object;
} ## --- end sub get_month_stats


sub math{

  my $self = shift;
 
  my $hash_params = {};
  my @arr_params = $self->param;
  my %hash_params = map{ $_ => $self->param($_); } @arr_params if( scalar( @arr_params ) );

  my $start_config = \%hash_params;

  warn $start_config->{monthly_rent};

  my $months = [];
  my $month = {
    num_aps => $start_config->{start_aparments_no},
    total_to_invest => $start_config->{monthly_investment}
      + $start_config->{start_aparments_no} * $start_config->{monthly_rent},
    cash => $start_config->{start_cash},
    debt => $start_config->{initial_debt},
  };
  my $result = { string => {} };
  my $i = 0;
  my $old_num_aps = $start_config->{start_aparments_no};

  #warn $start_config->{start_aparments_no};

  my $prev_debt = 0;

  while ( $i < $start_config->{total_months} ) {
    
    $month = next_month_stats($month, $start_config);        
    die "Error in month $i" . $month if ( $month->{debt} < 0 or $month->{credit_value} < 0 );
    $month = get_assets_value($month, $start_config );
    my %local_month = %$month;  	
	push( @{$months}, \%local_month );
	if ( $old_num_aps != $month->{num_aps} ) {
 	   $result->{string} = "month $i:" .Dumper($month);

	  # push @{$self->session->{success_messages} }, $result->{string} ;
	}
   
    $result->{string} = $result->{string} . "apartment no:" . $month->{num_aps} . " paid in month no: $i" if $prev_debt > 0 && $month->{debt} == 0;
    $old_num_aps = $month->{num_aps};
    $prev_debt = $month->{debt};

    $start_config->{apartment_value} *= ( 1 + ( $start_config->{apartment_appreciation} / 100 ) / 12 );
    $start_config->{monthly_rent} *= ( 1 + ( $start_config->{yearly_rent_increase} / 100 ) / 12 );
    $i++;
  }
  
  $self->render( {
	template => 'example/math',
	math => $months,
	} );
}


sub login {
  my $self = shift;
  
  $self->session->{user} = $self->_get_a_user();

  push @{ $self->session->{success_messages} },  'Congratulations, you have successfully logged in.' ;
  push @{ $self->session->{notice_messages} }, sprintf('Welcome %s %s.', $self->session->{user}->{first_name}, $self->session->{user}->{last_name} );

  $self->redirect_to('/');
}


sub logout{
  my $self = shift;

  $self->session( expires => 1);

  $self->redirect_to('/');
}

sub about{
  my $self = shift;
  
}

sub signed_in_about{
  my $self = shift;
  
  $self->render( {
    template  => 'example/about',
    user_type => $self->param('user_type'),
  } );
}

sub signed_in_menu{
  my $self = shift;
  
  $self->render( {
    template  => 'example/menu_page',
    user_type => $self->param('user_type'),
  } );
}
              

sub _get_a_user{
  my $self = shift;

  #randomly get a user from config
  return $self->app->{config}->{demo_users}->{ ( keys %{ $self->app->{config}->{demo_users} } )[ rand( scalar( keys %{ $self->app->{config}->{demo_users} } ) ) ] };
}


1;
