#########################################################################################
# CONCEPT GENERATOR         
# A Streamlit app that uses the Concept Generator service that was created in 
# Step 2b in the sfc-gh-pnanisetty/concept-generator-service repo.
#
# Creator: Prabhath Nanisetty (prabhath.nanisetty@snowflake.com)
#########################################################################################

# Import python packages
import json
import requests
import numpy as np
import pandas as pd
import streamlit as st
from typing import Optional
from PIL import Image, ImageDraw, ImageFont
from snowflake.ml.model import Model
from snowflake.cortex import complete
from snowflake.ml.registry import registry
from snowflake.snowpark.context import get_active_session

session = get_active_session()

#########################################################################################
# STEP 1 - DEFINE PARAMETERS         
# These need to be updated based on where you db, schema, model, and model_versions
# are after running the notebook.
#########################################################################################
DATABASE = 'CONCEPT_GEN_DB'
SCHEMA = 'CONCEPT_GEN_SCHEMA'
SERVICE = 'CONCEPT_GEN_SERVICE'
TEXT2IMAGE_MODEL = 'FLUX_1_schnell'
TEXT2IMAGE_MODEL_VERSION = 'HAPPY_RAY_4'
LLM_MODEL = 'llama3.1-70b'  # for generating taglines and concept drawing instructions

# Many sites will block hotlinking of URLs from python. In this case, we provide a 
# useragent that may pass depending on the site policy. Modify these to your information
USER_AGENT = 'ConceptGenDemo/1.0 (https://mycompany.com; myemailaddress@mycompany.com)'


#########################################################################################
# STEP 2 - DEFINE CORE FUNCTIONS
#########################################################################################

def get_image_service(db: str, schema: str, model: str, version: str) -> Model:
    """Loads the model from the Snowflake Model Registry"""
    reg = registry.Registry(session=session, database_name=db, schema_name=schema)
    mdl = reg.get_model(model).version(version)
    return mdl

def generate_background(prompt: str, service: str, model: Model) -> Image:
    """Generate the background image from our model"""
    model_output = model.run(pd.DataFrame([[prompt]]), service_name=service)
    return process_image(model_output["images"][0])

def generate_tagline(prompt: str, brand: str) -> str:
    """Create a witty marketing tagline"""
    instruction = """Please provide a witty advertising tagline that will be 
        displayed at the bottom of the image described below. Please do not 
        provide any additional text or descriptions, just the tagline only. 
        If the tagline is more than 8 words long please insert a new line character.
        Do not structure response in JSON, only a string."""

    user_prompt = brand + ' brand with a background of ' + prompt
    cortex_prompt = [
        {'role':'system', 'content': instruction},
        {'role':'user', 'content': user_prompt}
    ]
    
    return complete(LLM_MODEL, cortex_prompt)

def summarize_concept(concept: str, brand: str) -> str:
    """Summarize a concept idea or text into an idea"""
    instruction_1 = f'You are developing an image for advertising the {brand} brand. '
    instruction_2 = """Summarize the following idea into instructions for a text2image llm
                    model. Do not mention the name of the brand and do not request any text.
                    Instructions should be concise with limited usage of verbs and other
                    sentence structure. Do not include any text that is unrelated to the
                    instruction and return only a string, no JSON or other formatting."""
    instruction = instruction_1 + instruction_2

    cortex_prompt = [
        {'role':'system', 'content': instruction},
        {'role':'user', 'content': concept}
    ]

    return complete(LLM_MODEL, cortex_prompt)

def create_final_concept(logo: Optional[Image.Image], background: Image, msg: str, type: int=1) -> Image:
    """Overlay the logo (optional) on the background image and write the tagline at the bottom.
    These options and layouts can be modified. A `type` variable is included for later expansion
    to represent different forms or layouts of concepts."""
    
    width, height = background.size
    
    if logo is not None:
        logo_w, logo_h = logo.size
        if logo_w > width / 2 or logo_h > height / 5:
            maxsize = (width / 2, height / 5)
            logo.thumbnail(maxsize)
            
        background.paste(logo, (0,0), mask=logo)
    
    # Add a larger canvas to add a tagline at the bottom
    avg_color = get_average_color(background)
    img = Image.new(mode='RGB', size=(width, height+100), color=avg_color)
    img.paste(background, (0,0))
    
    # Add the tagline text to the image
    font = ImageFont.load_default(size=30)
    draw = ImageDraw.Draw(img)
    _, _, w, h = draw.textbbox((0,0), msg, font=font)
    draw.text(((width-w)/2, height + ((100-h)/2)), msg, font=font, 
              fill=get_complementary_color(avg_color))

    return img

#########################################################################################
# STEP 3 - DEFINE UTILITY FUNCTIONS FOR IMAGES
#########################################################################################

def process_image(raw_img: list) -> Image:
    """Convert raw image data to PIL Image type"""
    array = np.array(raw_img, dtype=np.uint8)
    img = Image.fromarray(array)
    return img

def get_average_color(img: Image) -> tuple:
    """Get the most common color"""
    array = np.array(img)
    avg = array.mean(axis=(0,1))
    return (int(avg[2]), int(avg[1]), int(avg[0]))

def get_complementary_color(rgb: tuple) -> tuple:
    """Returns the complementary color of the one provided"""
    r, g, b = rgb[0], rgb[1], rgb[2]
    # Calculate perceptive luminance - human eye favors green color
    # from: https://stackoverflow.com/questions/1855884/determine-font-color-based-on-background-color
    luminance = (0.299*r + 0.587*g + 0.114*b) / 255

    if luminance > 0.5:
        d = 0
    else:
        d = 255

    return (d, d ,d)

#########################################################################################
# STEP 4 - BUILD STREAMLIT UI
#########################################################################################

st.title(":snowflake: Snowflake Concept Test Idea Generator 🏞️💡")
st.write(
    """Use this to generate marketing or product concepts. Each final concept will contain
    a concept image, a marketing tagline, and optionally, a brand logo.
    """
)

# Define the various options and process flow
tab1, tab2, tab3, tab4, tab5 = st.tabs(['🍟 Provide a Logo', '📝 Concept Idea', '🤖 Pick Model', '⚙️ Customize', '🎬 Start!'])

with tab1:
    logo = st.radio('Include a logo?', ('No', 'Yes'))
    st.divider()
    logo_url = st.text_input('Provide a URL or Snowflake Stage location of a logo:', key=0, value='https://urltologo.com')
    st.write('Note 1: Stage location should be in the form: @<database_name>.<schema_name>.<stage_name>/<image_file_name>')
    st.write('Note 2: If you are using a URL, please make sure you have enabled an External Access Integration that will allow Snowflake to access the external domain.')

with tab2:
    idea = st.radio('Source of Idea?', ('Manual Input', 'From Table'))
    st.divider()
    st.write('Option 1: Enter a concept idea manually')
    brand_manual = st.text_input('Describe the brand:', key=2, value='Charisma paper towels')
    concept_manual = st.text_input('Provide the concept idea', key=3, value='Paper towels make it easier to take care of pet messes, especiallyl cleaning up around the dog food bowl')
    st.divider()
    st.write('Option 2: Select a concept idea from consumer interviews')
    choices_df = session.sql('select * from concept_gen_db.concept_gen_schema.idea_repository').to_pandas()
    selection = st.dataframe(data=choices_df, on_select='rerun', hide_index=True, selection_mode='single-row')
    if selection['selection']['rows']:
        brand_table = choices_df.iloc[selection['selection']['rows']]['PRODUCT'].iloc[0]
        concept_table = choices_df.iloc[selection['selection']['rows']]['IDEA_TEXT'].iloc[0]
        st.write('Brand: ' + brand_table)
        st.write('Concept: ' + concept_table)

with tab3:
    st.write('Only one model has been implemented in this version. Please skip to next tab')

with tab4:
    st.write('This is where you can customize the size and shape of the resulting image. Not implemented for this demo. Please skip to next tab.')

with tab5:
    st.write('NOTE: if you have suspended your service, it may take 20+ minutes to re-start the service for usage. This is because the container image needs to be loaded as a container. You may see errors in Streamlit if requests timeout.')
    st.write('To see the progress of the service, please run the utility code within the set-up SQL file.')
    st.write('Click below to start generating your concept.')
    submit = st.button('Generate Concept',key='generate')

# After submission, create and display the final concept image.
if submit:
    with st.status('Generating Concept Idea'):
        st.write('Loading Model from Registry')
        model = get_image_service(DATABASE, SCHEMA, TEXT2IMAGE_MODEL, TEXT2IMAGE_MODEL_VERSION)

        if logo == 'Yes':
            st.write('Getting logo image')
            headers = {'User-Agent': USER_AGENT}
            if logo_url[0] == '@':
                img_raw = session.file.get_stream(logo_url , decompress=False)
            else:
                img_raw = requests.get(logo_url, stream=True, headers=headers).raw
                         
            logo = Image.open(img_raw)
        else:
            logo = None

        st.write('Creating the final concept idea')
        if idea == 'Manual Input':
            final_concept = concept_manual
            final_brand = brand_manual
        else:
            final_concept = concept_table
            final_brand = brand_table
            
        concept_instructions = summarize_concept(final_concept, final_brand)
        
        st.write('Generating background')
        background = generate_background(concept_instructions, SERVICE, model)

        st.write('Generating Tagline')
        tagline = generate_tagline(final_concept, final_brand)

        st.write('Generating final concept')
        img_concept = create_final_concept(logo, background, tagline)

    with st.expander('Concept Idea'):
        st.write(final_concept)
    with st.expander('Concept Drawing Instructions'):
        st.write(concept_instructions)
    with st.expander('Tagline'):
        st.write(tagline)
    with st.expander('Concept'):
        st.image(img_concept)
