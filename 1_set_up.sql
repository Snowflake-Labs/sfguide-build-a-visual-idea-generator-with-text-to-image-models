////////////////////////////////////////////////////////////////////////////////////////////////////
// CONCEPT GENERATION DEMO
// This is the set-up script for the Concept generation demo
//
// There are a few general steps
// 1. Create a new role with appropriate privileges
// 2. Create compute engines
// 3. Create external integrations to access external resources like huggingface, pypi, and other sources
// 4. Create sample data to demonstrate concept image generation
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
// STEP 0 - CLEAN-UP & UTILITY FUNCTIONS - !*!*!*!*! DO NOT RUN AS PART OF SCRIPT !*!*!*!*!
// These are simple utility functions for cleanup/removal of the assets that are created 
// in this demo.
////////////////////////////////////////////////////////////////////////////////////////////////////

-- View created resources
SHOW COMPUTE POOLS;
SHOW EXTERNAL ACCESS INTEGRATIONS;
SHOW NETWORK RULES;
SHOW SERVICES;
SHOW MODELS;
SHOW VERSIONS IN MODEL FLUX_1_SCHNELL;

-- View Log files for new or existing services
SELECT SYSTEM$GET_SERVICE_LOGS('CONCEPT_GEN_SERVICE', 0, 'model-inference', 10);

-- Turn off compute resources & services
ALTER SERVICE CONCEPT_GEN_SERVICE SUSPEND;
ALTER COMPUTE POOL CONCEPT_GEN_POOL_L STOP ALL;
ALTER COMPUTE POOL CONCEPT_GEN_POOL_L SUSPEND;
ALTER COMPUTE POOL CONCEPT_GEN_POOL_M STOP ALL;
ALTER COMPUTE POOL CONCEPT_GEN_POOL_M SUSPEND;
ALTER COMPUTE POOL CONCEPT_GEN_SERVICE_POOL_L STOP ALL;
ALTER COMPUTE POOL CONCEPT_GEN_SERVICE_POOL_L SUSPEND;

-- Drop all resources
USE ROLE ACCOUNTADMIN;
DROP EXTERNAL ACCESS INTEGRATION PYPI_ACCESS_INTEGRATION;
DROP NETWORK RULE PYPI_NETWORK_RULE;
DROP EXTERNAL ACCESS INTEGRATION HUGGINGFACE_ACCESS_INTEGRATION;
DROP NETWORK RULE HUGGINGFACE_NETWORK_RULE;
DROP EXTERNAL ACCESS INTEGRATION WIKIMEDIA_ACCESS_INTEGRATION;
DROP NETWORK RULE WIKIMEDIA_NETWORK_RULE;
DROP COMPUTE POOL CONCEPT_GEN_POOL_L;
DROP COMPUTE POOL CONCEPT_GEN_POOL_M;
DROP TABLE IDEA_REPOSITORY;
DROP SCHEMA CONCEPT_GEN_SCHEMA;
DROP DATABASE CONCEPT_GEN_DB;


////////////////////////////////////////////////////////////////////////////////////////////////////
// STEP 1
// Create a new role and db / schema and object permission
// Why? ACCOUNTADMIN roles are not permitted to access compute pools directly
////////////////////////////////////////////////////////////////////////////////////////////////////

USE ROLE ACCOUNTADMIN;
CREATE ROLE IF NOT EXISTS CONCEPT_GEN_ROLE;

GRANT CREATE DATABASE ON ACCOUNT TO ROLE CONCEPT_GEN_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE CONCEPT_GEN_ROLE;
GRANT CREATE COMPUTE POOL ON ACCOUNT TO ROLE CONCEPT_GEN_ROLE;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE CONCEPT_GEN_ROLE;
GRANT MONITOR USAGE ON ACCOUNT TO ROLE CONCEPT_GEN_ROLE;
GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE CONCEPT_GEN_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE CONCEPT_GEN_ROLE;
GRANT ROLE CONCEPT_GEN_ROLE TO ROLE ACCOUNTADMIN;

// Create Database, Warehouse, and Image stage
USE ROLE CONCEPT_GEN_ROLE;
CREATE OR REPLACE DATABASE CONCEPT_GEN_DB;
CREATE OR REPLACE SCHEMA CONCEPT_GEN_SCHEMA;

USE DATABASE CONCEPT_GEN_DB;
USE SCHEMA CONCEPT_GEN_SCHEMA;

CREATE STAGE CONCEPT_GEN_INPUT_IMAGES
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  DIRECTORY = (ENABLE = TRUE);


////////////////////////////////////////////////////////////////////////////////////////////////////
// STEP 2
// Create the warehouse for the notebook and Compute Pools for the models
////////////////////////////////////////////////////////////////////////////////////////////////////

// Create the warehouse for notebook usage
// Note - this is not the compute that runs the models, just orchestrates the notebook itself.
CREATE OR REPLACE WAREHOUSE CONCEPT_GEN_NOTEBOOK_WH
    WAREHOUSE_SIZE = XSMALL
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE;

// We will create two separate pools for this demo
// Only a Medium sized GPU pool is needed to run the demo in a notebook, however,
// in order to create a service, we will need a large pool to load the entire model into
// GPU memory
CREATE COMPUTE POOL IF NOT EXISTS CONCEPT_GEN_POOL_M
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = GPU_NV_M
    AUTO_SUSPEND_SECS = 100
    AUTO_RESUME = true
    INITIALLY_SUSPENDED = true
    COMMENT = 'Medium pool for running the concept generator notebook';
    
CREATE COMPUTE POOL IF NOT EXISTS CONCEPT_GEN_POOL_L
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = GPU_NV_L
    AUTO_SUSPEND_SECS = 100
    AUTO_RESUME = true
    INITIALLY_SUSPENDED = true
    COMMENT = 'Large pool for creating a concept generator service';

    
////////////////////////////////////////////////////////////////////////////////////////////////////
// STEP 3
// Create the external access integrations that allow us to access pypi and hugging face
////////////////////////////////////////////////////////////////////////////////////////////////////
USE ROLE ACCOUNTADMIN;

-- Integration 1: Huggingface to download image LLM models
CREATE OR REPLACE NETWORK RULE HUGGINGFACE_NETWORK_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST= ('huggingface.co', 'cdn-lfs.huggingface.co', 'cdn-lfs-us-1.huggingface.co',
                 'cdn-lfs.hf.co', 'cdn-lfs-us-1.hf.co');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION HUGGINGFACE_ACCESS_INTEGRATION
    ALLOWED_NETWORK_RULES = (HUGGINGFACE_NETWORK_RULE)
    ENABLED = true;

GRANT USAGE ON INTEGRATION HUGGINGFACE_ACCESS_INTEGRATION TO ROLE CONCEPT_GEN_ROLE;

-- Integration 2: Pypi for access to key python packages like `diffusers`
CREATE OR REPLACE NETWORK RULE PYPI_NETWORK_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = ('pypi.org', 'pypi.python.org', 'pythonhosted.org',  'files.pythonhosted.org');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION PYPI_ACCESS_INTEGRATION
    ALLOWED_NETWORK_RULES = (PYPI_NETWORK_RULE)
    ENABLED = true;

GRANT USAGE ON INTEGRATION PYPI_ACCESS_INTEGRATION TO ROLE CONCEPT_GEN_ROLE;

-- Integration 3: Wikimedia and githubusercontent for access to images (like a brand logo or something)
CREATE OR REPLACE NETWORK RULE EXTERNAL_LOGO_NETWORK_RULE
    TYPE = HOST_PORT
    MODE = EGRESS
    VALUE_LIST = ('upload.wikimedia.org', 'raw.githubusercontent.com');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION EXTERNAL_LOGO_ACCESS_INTEGRATION
    ALLOWED_NETWORK_RULES = (EXTERNAL_LOGO_NETWORK_RULE)
    ENABLED = true;

GRANT USAGE ON INTEGRATION EXTERNAL_LOGO_ACCESS_INTEGRATION TO ROLE CONCEPT_GEN_ROLE;


////////////////////////////////////////////////////////////////////////////////////////////////////
// STEP 4
// Create sample data for use in our concept generation
// This dataset will attempt to simulate various customer comments
////////////////////////////////////////////////////////////////////////////////////////////////////
USE ROLE CONCEPT_GEN_ROLE;

-- Create a table of ideas
-- Using an article as a basis for paper towel ideas ( https://www.southernliving.com/paper-towel-uses-7563562 )
CREATE OR REPLACE TABLE IDEA_REPOSITORY (
    TITLE VARCHAR,
    PRODUCT VARCHAR,
    IDEA_TEXT VARCHAR
);

INSERT INTO IDEA_REPOSITORY (TITLE, PRODUCT, IDEA_TEXT)
VALUES
  (
    'DIY Wet Cleaning Wipes',
    'Charisma Paper Towels',
    'Do it yourself wet cleaning wipes. Out of classic wet wipes or disinfecting cloths? Paper towels can easily be transformed into a homemade version of a cleaning cloth. Moisten the disposable sheets with water and a gentle cleaning agent like dish soap, then use the DIY wet wipes to clean countertops or messy faces.'
  ),

  (
    'Keep Produce Fresher',
    'Charisma Paper Towels',
    'Keep Produce Fresher. Another handy way to keep your produce fresh for as long as possible is to line your refrigerator''s crisper drawer with paper towels. The sheets will absorb excess moisture, which will prevent your fruits and veggies spoiling quickly.'
  ),

  (
    'Shoe Freshener',
    'Charisma Paper Towels',
    'The next time your stinky sneakers and overworked sock shoes need freshening, fight those unpleasant odors with paper towels. Add a few drops of essential oil (peppermint works wonders) to paper towels, crumple them up, and tuck them inside your shoes. Leave them overnight for footwear that smells much fresher in the morning.'
  ),

  (
    'Prevent Microwave Messes',
    'Charisma Paper Towels',
    'Prevent Microwave Messes. The next time you reheat fried rice or mac and cheese, keep your microwave clean by placing a slightly damp paper towel over the container. This should prevent messy splatters and eliminate the need to scrub off pesky dried food stains.'
  ),

  (
    'Biscuits and Soup Recipe',
    'Bluebell''s Soup',
    'I poured hot soup over biscuits. For supper.'
  ),

  (
    'Granola Ideas for Breakfast',
    'Starts with K Granola',
    'Great with yogurt or to create your own granola bars. I find these to be neutral enough in flavor and texture, to please most everybody''s preferences when it comes to granola. You can of course eat this with milk, but I have also added some to a smoothie to give it some thickness and crunch, it helps make a more filling drink so I don''t feel the need to snack in between meals.'
  ),
  
  (
    'Granola Yogurt Cups',
    'Starts with K Granola',
    'I love this granola! I was forced to order off Amazon after not being able to find on a store shelf and I''ll keep ordering from here now! This is a great product for snacking, I put it in my flavored yogurt cups. It definitely satisfies the sweet and crunchy flavor at the same time!'
  ),

  (
    'Berry It Alive Positive Review',
    'Liquid Coffin Brand Flavored Sparkling Water',
    'I recently tried Liquid Death Sparkling Water in the Berry It Alive flavor, and it has quickly become my go-to beverage. The berry flavor is incredibly refreshing and perfectly balanced—not too sweet, but just right. The use of real agave nectar adds a subtle sweetness that enhances the overall taste without being overpowering. The 16.9 oz. tallboy cans are not only convenient but also eco-friendly, as they are made from infinitely recyclable aluminum. I appreciate Liquid Death’s commitment to reducing plastic waste. The carbonation level is spot-on, providing a satisfying fizz that quenches my thirst every time. One of the standout features is the unique and edgy branding, which makes drinking this sparkling water a fun experience. It’s a great conversation starter and adds a bit of excitement to my daily hydration routine. Overall, I highly recommend Liquid Death Berry It Alive to anyone looking for a delicious and environmentally conscious sparkling water option.'
  )
;
    
