# Use the official lightweight Node.js 18 Alpine image
FROM node:18-alpine

# Set working directory inside the container
WORKDIR /app

# Copy package.json first to leverage Docker layer caching
COPY app/package.json ./

# Install production dependencies only
RUN npm install --omit=dev

# Copy the rest of the application source code
COPY app/ ./

# Expose the port the app listens on
EXPOSE 3000

# Start the application
CMD ["node", "app.js"]
