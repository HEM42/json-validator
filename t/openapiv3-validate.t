use lib '.';
use t::Helper;
use JSON::Validator::Schema::OpenAPIv3;
use Test::Deep;
use Test::More;

my %params = (get_req => [], get_params => [], set_params => []);
my $cwd    = Mojo::File->new(__FILE__)->dirname;
my $schema = JSON::Validator::Schema::OpenAPIv3->new->data(
  $cwd->child(qw(spec v3-petstore.json)));
my $c = t::Helper->controller(\%params);

note 'dummy data from http request';
$params{get_req} = [
  {
    in           => 'body',
    name         => 'body',
    content_type => 'application/json',
    exists       => 0,
  },
];

note 'missing body';
my @errors = $schema->validate_request($c, post => '/pets');
is_deeply \@errors, [E('/body', 'Missing property.')], 'missing body';

note 'input to $c->openapi->get_request_data';
cmp_deeply(
  $params{get_params},
  [
    superhashof({in => 'cookie', name => 'debug'}),
    superhashof({
      in      => 'body',
      name    => 'body',
      accepts => {
        'application/x-www-form-urlencoded' => ignore,
        'application/json'                  => ignore,
      },
    }),
  ],
  'c.openapi.get_request_data',
);

note 'missing body parameter';
$params{get_req}[0]{exists} = 1;
$params{get_req}[0]{value}  = {name => 'Goma'};
@errors                     = $schema->validate_request($c, post => '/pets');
is_deeply \@errors, [E('/body/id', 'Missing property.')], 'errors';

note 'valid body';
$params{get_req}[0]{value} = {id => 42, name => 'Goma'};
@errors = $schema->validate_request($c, post => '/pets');
is_deeply \@errors, [], 'valid body';

note 'valid input';

done_testing;
