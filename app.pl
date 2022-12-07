#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::JSON;
use Modern::Perl '2013';
use Try::Tiny;
use Data::Dumper;
use WebHooks::Schema;
use Support::Schema;
use POSIX qw(strftime);
use Time::Piece;



my $config = plugin 'JSONConfig';
# my $json   = Mojo::JSON->new;


# Get a UserAgent
my $ua = Mojo::UserAgent->new;

# WhatCounts setup
my $API        = $config->{'wc_api_url'};
my $wc_list_id = $config->{'wc_listid'};
my $wc_realm   = $config->{'wc_realm'};
my $wc_pw      = $config->{'wc_password'};
my $secret     = $config->{'tw_secret'};

    my %args = (
        r => $wc_realm,
        p => $wc_pw,
    );

my %wc_to_db;

helper dbh => sub {
    my $schema = WebHooks::Schema->connect( $config->{'pg_dsn'},
        $config->{'pg_user'}, $config->{'pg_pass'}, );
    return $schema;
};


helper dbhsupport => sub  {
    my $schema = Support::Schema->connect( $config->{'pg_dsn'},
        $config->{'pg_user'}, $config->{'pg_pass'}, );
    return $schema;
};


helper find_or_new => sub {
    my $self       = shift;
    my $subscriber = shift;
    my $dbh        = $self->dbh();
    my $result;
    try {
        $result = $dbh->txn_do(
            sub {
                my $rs = $dbh->resultset( 'Wufoo' )
                    ->find_or_new( { %$subscriber, } );
                unless ( $rs->in_storage ) {
                    $rs->insert;
                }
            }
        );
    }
    catch {
        $self->app->log->debug( $_ );
    };
    return $result;
};


get '/' => sub {
    my $c = shift;
  $c->render(text => 'Hello World! Recurly');

};

post '/recurly' => sub {
    my $notify;
    my $self = shift;
    my $post = shift;
        my $dom   = $self->req->dom;
        my $body = $self->req->body;
    use XML::Simple;
    my $xs = XML::Simple->new();
    my $xms = $xs->XMLin($body, KeepRoot => 1);
    my $hooktype = ( keys( $xms))[0] ;
    my $lasttrans;
    my $email = $xms->{$hooktype}{account}{email};
    my $builder_plan;
    my $amount;
       my $ub = Mojo::UserAgent->new;    
      my $merge_fields = {};
    
   my $successText = 'Please check your inbox for an email from thetyee.ca containing a confirmation message';
    my $successHtml = '<h2><span class="glyphicon glyphicon-check" aria-hidden="true">';
    $successHtml   .= '</span>&nbsp;Almost done</h2>';
    $successHtml   .= '<p> ' . $successText . '</p>';
    my $errorText = 'There was a problem with your subscription. Please e-mail helpfulfish@thetyee.ca to be added to the list.';
    my $errorHtml = '<p>' . $errorText . '</p>';
    my $notification;
    my $date;

    
    if ($hooktype eq 'new_subscription_notification') {
$notification .= "$email parsing $hooktype" unless $email eq 'api@thetyee.ca';  
             $date = $xms->{$hooktype}{subscription}{current_period_started_at}{content};
        my $t = Time::Piece->strptime($date, "%Y-%m-%dT%H:%M:%SZ");
         my $mctime = $t->strftime("%m/%d/%Y");
     
     
        $merge_fields->{'B_L_T_DATE'} = $mctime;
        $merge_fields->{'B_PLAN'} = $xms->{$hooktype}{subscription}{plan}{plan_code};
        $merge_fields->{'B_LEVEL'} = ($xms->{$hooktype}{subscription}{total_amount_in_cents}{content} / 100);
        $merge_fields->{'BUILDER'} = 1;
    
    
    } elsif ($hooktype eq 'renewed_subscription_notification') {
$notification .= "$email parsing $hooktype" unless $email eq 'api@thetyee.ca';  
                  $date = $xms->{$hooktype}{subscription}{current_period_started_at}{content};
        my $t = Time::Piece->strptime($date, "%Y-%m-%dT%H:%M:%SZ");
         my $mctime = $t->strftime("%m/%d/%Y");
         
        $merge_fields->{'B_L_T_DATE'} = $mctime;
        $merge_fields->{'B_LEVEL'} = ($xms->{$hooktype}{subscription}{total_amount_in_cents}{content} / 100);
        $merge_fields->{'B_PLAN'} = $xms->{$hooktype}{subscription}{plan}{plan_code};
        $merge_fields->{'BUILDER'} = 1;

    } elsif ($hooktype eq 'successful_payment_notification' &&  ref($xms->{$hooktype}{transaction}{subscription_id}) && $xms->{$hooktype}{transaction}{subscription_id}{nil} && $xms->{$hooktype}{transaction}{subscription_id}{nil} eq 'true') {      
$notification .= "$email parsing $hooktype" unless $email eq 'api@thetyee.ca';  

        $merge_fields->{'B_ONETIME'} = 1;
        $merge_fields->{'B_ONE_AMT'} = ($xms->{$hooktype}{transaction}{amount_in_cents}{content}  / 100);
        $date = $xms->{$hooktype}{transaction}{date}{content};
        my $t = Time::Piece->strptime($date, "%Y-%m-%dT%H:%M:%SZ");
        my $mctime = $t->strftime("%m/%d/%Y");
        $merge_fields->{'ONETIME_DT'} = $mctime;
        
    } elsif ($hooktype eq 'updated_subscription_notification') {
$notification .= "$email parsing $hooktype" unless $email eq 'api@thetyee.ca';  
        $merge_fields->{'BUILDER'} = 1;
        $date = $xms->{$hooktype}{subscription}{current_period_started_at}{content};
        my $t = Time::Piece->strptime($date, "%Y-%m-%dT%H:%M:%SZ");
        my $mctime = $t->strftime("%m/%d/%Y");
        $merge_fields->{'B_L_T_DATE'} = $mctime;
        $merge_fields->{'B_PLAN'} = $xms->{$hooktype}{subscription}{plan}{plan_code};   
     } elsif ($hooktype eq 'expired_subscription_notification' || $hooktype eq 'canceled_subscription_notification') {
$notification .= "$email parsing $hooktype" unless $email eq 'api@thetyee.ca';  
        my $t = Time::Piece->strptime($date, "%Y-%m-%dT%H:%M:%SZ");
        my $mctime = $t->strftime("%m/%d/%Y");
        $merge_fields->{'B_L_T_DATE'} =  $mctime;   
        $merge_fields->{'B_C_DATE'} = $mctime;
        $merge_fields->{'B_PLAN'} = 'cancelled';
        $merge_fields->{'BUILDER'} = 0;
    } else {
            $self->app->log->debug('99 transtype is ' . $hooktype);    
            $self->app->log->debug( '991 no webhooks of use here' );
          return $self->render(text => '992 Nothing to update', status => '204');           
    }   
# find the record
       my $search_args = {
        email_address => $email,
         status_if_new => 'subscribed',
         merge_fields => $merge_fields,

        status => 'subscribed'   
        };
    my $search; my $result;
    
use Digest::MD5 qw(md5 md5_hex md5_base64);

my $emailmd5 = md5_hex($email);

   
 
 my $uget = Mojo::UserAgent->new;
  my $getresult;
my $GETURL =   Mojo::URL->new('https://' . $config->{'mc_user'} . ':' . $config->{'mc_api_key'} . '@' . $config->{'mc_api'} . '/3.0/lists/979b7d233e/members/'. $emailmd5);
 my $gettx = $uget->get( $GETURL  );
  my $getjs = $gettx->result->json;    

     app->log->debug( "993 code" . $gettx->res->code);
      app->log->debug( "993.1 " . Dumper( $getjs));
     app->log->debug( "994 unique email id" .  $getjs->{'unique_email_id'});
     if ($gettx->res->code == 200 ) {
        $getresult = $gettx->result->body;
        # Output response when debugging
      #          app->log->debug( Dumper( $tx  ) );
      #  app->log->debug( Dumper( $result ) );
        if ( $getresult =~ 'subscribed' ) {
            my $subscriberId = $getjs->{'unique_email_id'};
        }
     
     
 
  my $URL = Mojo::URL->new('https://' . $config->{'mc_user'} . ':' . $config->{'mc_api_key'} . '@' . $config->{'mc_api'} . '/3.0/lists/979b7d233e/members/'. $emailmd5);
 my $tx = $ua->put( $URL => json => $search_args );
    
   my $js = $tx->result->json;
     app->log->debug( "995 code" . $tx->res->code);
 app->log->debug( Dumper( "995.1 \n" . $tx));
      app->log->debug( "995.2 \n" . Dumper( $js));
      $notification .=  "995.2 \n" . Dumper( $js);
     app->log->debug( "996 unique email id" .  $js->{'unique_email_id'});
  
# check params at https://docs.mojolicious.org/Mojo/Transaction/HTTP
  
    if ($tx->res->code == 200 ) {
        $result = $tx->result->body;
        # Output response when debugging
      #          app->log->debug( Dumper( $tx  ) );
      #  app->log->debug( Dumper( $result ) );
        if ( $result =~ 'subscribed' ) {
            my $subscriberId = $js->{'unique_email_id'};
            # Send 200 back to the request
            $self->render( json => { 
                    text => $successText, 
                    html => $successHtml, 
                    subcriberId => $subscriberId, 
                    resultStr => $result }, 
                status => 200 );
$notification = $email . "updated based on recurly webhook.";
            app->log->info(" 997 " .$notification) unless $email eq 'api@thetyee.ca';
         
          } else {
            $self->render( json => { 
                    text => $errorText, 
                    html => $errorHtml, 
                    resultStr => $result }, 
                status => 500 );
		$notification = $email . ", failure? return did not contain 'subscribed'.   error: " .$errorText;
		app->log->info(" 998 " .$email . ", failure \n") unless $email eq 'api@thetyee.ca';
          }
    } else {
        my ( $err, $code ) = $tx->error;
        $result = $code ? "$code response: $err" : "Connection error: " . $err->{'message'};
        # TODO this needs to notify us of a problem
        app->log->debug( "999 " . Dumper( $result ) );
        # Send a 500 back to the request, along with a helpful message
            $self->render( json => { 
                    text => $errorText, 
                    html => $errorHtml, 
                    resultStr => $result }, 
                status => 500 );
	app->log->info("9910 error: "  . $errorText) unless $email eq 'api@thetyee.ca';
            app->log->debug("9911 error: "  . $errorText);
                    $ub->post($config->{'notify_url'} => json => {text => "error: $errorText \n" }) unless $email eq 'api@thetyee.ca'; 
            
    }
    
    
     } else {
      app->log->info("9912 email  $email not found on mailchimp. END");
      
 


    
# $self->app->log->debug( Dumper( $xms ) );
        $self->app->log->debug('9913 transtype is ' . $hooktype);    
        $self->app->log->debug("9914 return from WC search \n " . $search);    
        $self->app->log->debug("9915 return from WC update \n " . Dumper( $result));
#        $self->app->log->debug("update csv for whatcounts" . $updatecsv);    

    $self->respond_to(   
        any  => {data => '', status => 204}
    );


    
};

if ($notification) {$ub->post($config->{'notify_url'} => json => {text => $notification }) unless $email eq 'api@thetyee.ca'; }



};


# app->secret( $config->{'app_secret'} );

app->start;
