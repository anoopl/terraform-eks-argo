from fastapi import FastAPI

app = FastAPI()


@app.get("/")
async def root():
    return {"version": "0.1.0"}
