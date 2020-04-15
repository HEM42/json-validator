use lib '.';
use t::Helper;
use JSON::Validator::Schema::OpenAPIv2;
use Test::Deep;
use Test::More;

my %params = (get_req => [], get_params => [], set_params => []);
my $schema
  = JSON::Validator::Schema::OpenAPIv2->new->data('data://main/defaults.json');
my $c = t::Helper->controller(\%params);

note 'default in body';
{
  $params{get_req} = [
    {
      in     => 'body',
      name   => 'body',
      exists => 1,
      value  => {id => 42, name => 'Goma'}
    },
  ];
  my @errors = $schema->validate_request($c, post => '/pets');
  is_deeply \@errors, [], 'valid request';
  cmp_deeply(
    $params{get_req},
    [
      superhashof({
        in    => 'body',
        name  => 'body',
        value => {id => 42, name => 'Goma', tag => 'Mouse'},
      }),
    ],
    'default set in body param',
  );
}

note 'default in query';
{
  %params = (get_req => [], get_params => [], set_params => []);
  $params{get_req} = [{in => 'query', name => 'limit', exists => 0}];
  my @errors = $schema->validate_request($c, get => '/pets');
  is_deeply \@errors, [], 'valid request';
  cmp_deeply(
    $params{get_req},
    [superhashof({in => 'query', name => 'limit', value => 42, exists => 1})],
    'default set in query param',
  );
}

done_testing;

__DATA__
@@ defaults.json
{
  "swagger": "2.0",
  "info": {
    "version": "1.0.0",
    "title": "Swagger Petstore",
    "contact": {"name": "OAI", "url": "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/master/examples/v2.0/json/petstore.json"},
    "license": {"name": "MIT"}
  },
  "host": "petstore.swagger.io",
  "basePath": "/v1",
  "schemes": ["http"],
  "consumes": ["application/json"],
  "produces": ["application/json"],
  "paths": {
    "/pets": {
      "get": {
        "summary": "List all pets",
        "operationId": "listPets",
        "tags": ["pets"],
        "parameters": [
          {"default": 42, "name": "limit", "in": "query", "description": "How many items to return at one time (max 100)", "required": false, "type": "integer", "format": "int32"}
        ],
        "responses": {
          "201": {
            "description": "Null response"
          }
        }
      },
      "post": {
        "summary": "Create a pet",
        "operationId": "createPets",
        "tags": ["pets"],
        "parameters": [
          { "in": "body", "name": "body", "required": true, "schema": { "$ref" : "#/definitions/Pet" } }
        ],
        "responses": {
          "201": {
            "description": "Null response"
          }
        }
      }
    }
  },
  "definitions": {
    "Pet": {
      "required": ["id", "name"],
      "properties": {
        "id": {"type": "integer", "format": "int64"},
        "name": {"type": "string"},
        "tag": {"type": "string", "default": "Mouse"}
      }
    },
    "Pets": {
      "type": "array",
      "items": {"$ref": "#/definitions/Pet"}
    }
  }
}
