shader_type canvas_item;

uniform sampler2D unlitTexture; // Texture for binary 0
uniform sampler2D litTexture; // Texture for binary 1
uniform sampler2D binaryDataTexture; // 2D texture for binary data
uniform int gridWidth;      // Number of cells horizontally and vertically

const int cellSize = 8;    // Cell size in pixels
const float fadeDistance = 32.0; // Distance from border where fading starts

void fragment() {
	vec2 totalGridSize = vec2(float(gridWidth) * float(cellSize));
	
	vec2 scaledUV = UV * float(gridWidth);
	
	ivec2 cellIndex = ivec2(floor(scaledUV));
	
	vec2 cellUV = fract(scaledUV);
	bool isInsideCell = all(greaterThanEqual(cellUV, vec2(0.0))) && all(lessThan(cellUV, vec2(1.0)));
	
	vec2 binaryDataUV = vec2(
		float(cellIndex.x) / float(gridWidth - 1),
		float(cellIndex.y) / float(gridWidth - 1)
	);
	
	float binaryValue = texture(binaryDataTexture, binaryDataUV).r;
	
	bool isWhite = binaryValue > 0.5;
	
	float distanceX = min(scaledUV.x, float(gridWidth) - scaledUV.x) * float(cellSize);
	float distanceY = min(scaledUV.y, float(gridWidth) - scaledUV.y) * float(cellSize);
	float distanceToBorder = min(distanceX, distanceY);
	
	vec4 color = texture(unlitTexture, cellUV);
	
	if(isWhite && isInsideCell){
		color = texture(litTexture, cellUV);
	}
	
	float alphaFactor = log(distanceToBorder) / log(fadeDistance);
	color.a *= alphaFactor;
	
	COLOR = color;
}
