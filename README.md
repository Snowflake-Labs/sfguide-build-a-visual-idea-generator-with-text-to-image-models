# sfguide-build-a-visual-idea-generator-with-text-to-image-models
A companion repo for the Snowflake Quickstart. This quickstart will guide you to build a Streamlit application that can be a Visual Concept or Idea Generator. The Streamlit app is powered by a Text-to-Image model that will be accessed via a Service function that calls a Model in the Snowflake Model Registry.



## Step-by-Step Guide
For prerequisites, environment setup, step-by-step guide and instructions, please refer to the QuickStart Guide (link tbd).

## Other Notes
### Notebook Settings
#### General Tab
* SQL Warehouse - Choose the warehouse created in Step 1
* Python Environment - Run on Container
* Runtime - GPU
* Compute Pool - Choose the large pool created in Step 1 CONCEPT_GEN_POOL_L
* Idle timeout - 1 hour

#### External Access Tab
This may not appear when you create the notebook. After creation, click on the three dots in top right corner of Notebook and select Notebook Settings...
* Toggle on all the EAI's created in Step 1
* If you create additional EAIs, for say additional logo images from URLs, you will need to turn those on before calling from a notebook.

### FAQ
#### 1. What if I get a CUDA out of memory error?
Likely this happens when you do not have enough GPU to run the model. If you are OK with running the concept service in a notebook, simply replace the line similar to `pipeline.to('cuda')` with `pipeline.enable_sequential_cpu_offload()`. This will allow the model to only load components it really needs into GPU memory while keeping everything else via CPU. This may make generation slower.

#### 2. I'm getting an error at this step `logo = Image.open(img_raw)` in the Streamlit app
There could be many issues, but the most common one is that the URL you are attempting to pull an image from has blocked you. The previous step with the `requests.get` call is the culprit, but what was returned was a error message vs an image. In this case, you can try to change the USER_AGENT variable to conform to the site policy of the site you are using.

#### 3. Are there other Text 2 Image models that I can use?
Yes! FLUX.1-Schnell is a relatively new model from black forest labs. There are more competant models in the FLUX.1 family like Dev, which use more VRAM. On the less VRAM side, Stable Diffusion 1.5, 2.0, and SDXL have all been tested and work - as a bonus, you can run the SD models using GPU_NV_M or Medium sized GPUs with 24-30GB of VRAM.
