use lib '.';
use t::Helper;
use JSON::Validator::Schema::OpenAPIv3;
use Test::Deep;
use Test::More;

use DDP;

my %params = (get_req => [], get_params => [], set_params => []);
my $schema
  = JSON::Validator::Schema::OpenAPIv3->new->data('data://main/defaults.json');
my $c = t::Helper->controller(\%params);

note 'default in body';
{
  $params{get_req} = [
    {in => 'cookie', name => 'debug', exists => 0,},
    {
      in           => 'body',
      name         => 'body',
      content_type => 'application/json',
      exists       => 1,
      value        => {id => 42, name => 'Goma'}
    },
  ];
  my @errors = $schema->validate_request($c, post => '/pets');
  is_deeply \@errors, [], 'valid request';
  cmp_deeply(
    $params{get_req},
    [
      superhashof({in => 'cookie', name => 'debug'}),
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
  "openapi": "3.0.0",
  "info": {
    "license": {
      "name": "MIT"
    },
    "title": "Swagger Petstore",
    "version": "1.0.0"
  },
  "servers": [
    { "url": "http://petstore.swagger.io/v1" }
  ],
  "paths": {
    "/pets/{petId}": {
      "get": {
        "operationId": "showPetById",
        "tags": [ "pets" ],
        "summary": "Info for a specific pet",
        "parameters": [
          { "description": "The id of the pet to retrieve", "in": "path", "name": "petId", "required": true, "schema": { "type": "string" } },
          { "description": "Indicates if the age is wanted in the response object", "in": "query", "name": "wantAge", "schema": { "type": "boolean" } }
        ],
        "responses": {
          "default": {
            "description": "unexpected error",
            "content": {
              "application/json": { "schema": { "$ref": "#/components/schemas/Error" } },
              "application/xml": { "schema": { "$ref": "#/components/schemas/Error" } }
            }
          },
          "200": {
            "description": "Expected response to a valid request",
            "content": {
              "application/json": { "schema": { "$ref": "#/components/schemas/Pet" } },
              "application/xml": { "schema": { "$ref": "#/components/schemas/Pet" } }
            }
          }
        }
      }
    },
    "/pets": {
      "get": {
        "operationId": "listPets",
        "summary": "List all pets",
        "tags": [ "pets" ],
        "parameters": [
          { "default": 42, "description": "How many items to return at one time (max 100)", "in": "query", "name": "limit", "required": false, "schema": { "type": "integer", "format": "int32" }}
        ],
        "responses": {
          "200": {
            "description": "An paged array of pets",
            "headers": {
              "x-next": { "schema": { "type": "string" }, "description": "A link to the next page of responses"}
            },
            "content": {
              "application/json": { "schema": { "$ref": "#/components/schemas/Pets" } },
              "application/xml": { "schema": { "$ref": "#/components/schemas/Pets" } }
            }
          },
          "default": {
            "description": "unexpected error",
            "content": {
              "application/json": { "schema": { "$ref": "#/components/schemas/Error" } },
              "application/xml": { "schema": { "$ref": "#/components/schemas/Error" } }
            }
          }
        }
      },
      "post": {
        "operationId": "createPets",
        "summary": "Create a pet",
        "tags": [ "pets" ],
        "parameters": [
          { "description": "Turn on/off debug", "in": "cookie", "name": "debug", "schema": { "type": "integer", "enum": [0, 1] } }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": { "schema": { "$ref": "#/components/schemas/Pet" } },
            "application/x-www-form-urlencoded": { "schema": { "$ref": "#/components/schemas/Pet" } }
          }
        },
        "responses": {
          "201": {
            "description": "Null response",
            "content": {
              "*/*": { "schema": { "type": "string" } }
            }
          },
          "default": {
            "description": "unexpected error",
            "content": {
              "*/*": { "schema": { "$ref": "#/components/schemas/Error" } }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Pets": {
        "type": "array",
        "items": { "$ref": "#/components/schemas/Pet" }
      },
      "Pet": {
        "required": [ "id", "name" ],
        "properties": {
          "tag": { "type": "string", "default": "Mouse" },
          "id": { "type": "integer", "format": "int64" },
          "name": { "type": "string" },
          "age": { "type": "integer" }
        }
      },
      "Error": {
        "required": [ "code", "message" ],
        "properties": {
          "code": { "format": "int32", "type": "integer" },
          "message": { "type": "string" }
        }
      }
    }
  }
}
