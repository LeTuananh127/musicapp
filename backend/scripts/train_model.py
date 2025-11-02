"""
Train the recommendation model and reload it in the service.
Can be run manually or scheduled.
"""
import sys
import os
from pathlib import Path

# Add backend to path
backend_dir = Path(__file__).parent.parent
sys.path.insert(0, str(backend_dir))

from tools.train_recommender import main as train_main
from app.services.ml_recommendation_service import ml_recommendation_service
from app.core.db import SessionLocal
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def main():
    """Train model and reload service."""
    try:
        # Step 1: Train the model
        logger.info("Starting model training...")
        train_main()
        logger.info("Model training completed")
        
        # Step 2: Reload model in service
        logger.info("Reloading model in ML recommendation service...")
        ml_recommendation_service.reload_model()
        logger.info("Model reloaded successfully")
        
        # Step 3: Save user embeddings to database
        logger.info("Saving user embeddings to database...")
        db = SessionLocal()
        try:
            ml_recommendation_service.save_user_embeddings_to_db(db)
            logger.info("User embeddings saved successfully")
        finally:
            db.close()
        
        logger.info("Training pipeline completed successfully")
        return 0
        
    except Exception as e:
        logger.error(f"Training pipeline failed: {str(e)}", exc_info=True)
        return 1

if __name__ == "__main__":
    sys.exit(main())
